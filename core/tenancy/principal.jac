"""Per-tenant service principals (ADR-0003).

The only module allowed to use the runtime internals that create a principal and
switch the request's root to it. Contract tests: tests/spikes/s1_*_tests.jac and
s2_*_tests.jac, so a Jac upgrade that changes these internals fails CI.

Rules (ADR-0003):
- Every `act_as` is paired with `restore` in a `finally`.
- Flush (`flush_now`) before switching identity whenever the current identity has
  pending changes: the end-of-request flush re-checks write access under whichever
  root is current then, and silently drops rows it can't write (JI-020).
- Never `Jac.commit()` inside a request: it COMMITs the transaction midway, so a
  replay (read-tier upgrade or write conflict) would leave half the work applied.
  `flush_now` writes into the same open transaction instead.
- The read tier is off (`JAC_DB_RO_UNITS=0`, set here, for every app that imports this
  module). With it on, an endpoint the process hasn't seen write for 5 minutes runs
  read-only, and its first write re-runs the whole request: after a `commit_now`, that
  repeats work already committed (a sale or a scan done twice, JI-042).
"""

import os;
import secrets;
import from uuid { UUID, uuid4 }
import from jaclang { JacRuntime as Jac }
import from jaclang.runtime.exceptions { WriteConflict }

glob PRINCIPAL_PREFIX: str = "svc-tenant-";

def _read_tier_off -> bool {
    # Every request at SERIALIZABLE from its start: no read-only tier to upgrade from
    # by re-running a request that already committed part of its work (JI-042). The
    # runtime reads it per request, so setting it at import is enough.
    os.environ["JAC_DB_RO_UNITS"] = "0";
    return True;
}

glob READ_TIER_OFF: bool = _read_tier_off();

obj Principal {
    has user_id: str,
        root_id: str;
}

def node_id(node_obj: any) -> str {  # jac:ignore[W1037]
    return str(node_obj.__jac__.id);
}

def owner_id(node_obj: any) -> str {  # jac:ignore[W1037]
    return str(getattr(node_obj.__jac__, "root"));
}

def access_level(target: any) -> str {  # jac:ignore[W1037]
    return str(Jac.check_access_level(target.__jac__).name);
}

def _users -> any {  # jac:ignore[W1037]
    return Jac.get_user_manager(Jac.get_context().base_path_dir or "");
}

def create_principal(label: str) -> Principal {
    # An internal user whose random password is never stored or returned, so nobody
    # can log in as it (ADR-0003).
    users = _users();
    created = users.create_internal_user(
        f"{PRINCIPAL_PREFIX}{secrets.token_hex(8)}", secrets.token_urlsafe(32)
    );
    if "error" in created {
        raise RuntimeError(f"could not create the principal for {label}: {created}");
    }
    user_id = str(created["user_id"]);
    root_id = users.ensure_user_root(user_id);
    if not root_id {
        users.delete_user(user_id);
        raise RuntimeError(f"the principal for {label} has no root");
    }
    return Principal(user_id=user_id, root_id=str(root_id));
}

def new_principal(label: str) -> str {
    # Returns the principal's root id (the Phase 1 spikes use this form).
    return create_principal(label).root_id;
}

def delete_principal(user_id: str) {
    # Compensation for a failed signup: the identity store is outside the graph
    # transaction, so a rolled-back signup must remove its principal explicitly.
    _users().delete_user(user_id);
}

def _is_principal(user: dict[str, any]) -> bool {  # jac:ignore[W1037] a raw identity-store document
    # Identities are {"type", "value_raw", "value_normalized", ...}; principals have a
    # username identity with the svc-tenant- prefix.
    return any(
        str(i.get("value_normalized", "")).startswith(PRINCIPAL_PREFIX)
        for i in user.get("identities", [])
    );
}

def count_principals -> int {
    users = _users();
    total = 0;
    offset = 0;
    while True {
        page = users.list_all_users(500, offset);
        total += len(
            [
                u
                for u in page
                if _is_principal(u)
            ]
        );
        if len(page) < 500 {
            return total;
        }
        offset += 500;
    }
}

def fresh_node_id -> str {
    return str(uuid4());
}

def assign_id(node_obj: any, node_id_str: str) {  # jac:ignore[W1037]
    # Give a node its id before it is first persisted, so a claim can be made for it
    # before the node exists (ADR-0007: claim first, then create).
    node_obj.__jac__.id = UUID(node_id_str);
}

def system_root_id -> str {
    # Jac's system root: what static @schedule tasks run as, with WRITE on everything.
    # Act as it only to append to system-owned inboxes (ADR-0005), never to read on
    # a caller's behalf.
    return str(Jac.get_context().system_root.id);
}

def act_as(root_id: str) -> str {
    # Switch the request's root; nodes created until `restore` are owned by `root_id`.
    # Returns the previous root id for `restore`.
    ctx = Jac.get_context();
    previous = str(ctx.user_root.id);
    ctx.set_user_root(root_id);
    return previous;
}

def restore(previous_root_id: str) {
    Jac.get_context().set_user_root(previous_root_id);
}

def _serialization_failure(error: Exception) -> bool {
    # PostgreSQL refused the write because a concurrent transaction changed the same row
    # (40001) or deadlocked with it (40P01). The error carries the server's fields as a
    # dict whose "C" is the SQLSTATE code; look along the cause chain, as Jac does.
    seen = 0;
    current: any = error;  # jac:ignore[W1037]
    while current is not None and seen < 8 {
        for arg in getattr(current, "args", ()) {
            if isinstance(arg, dict) and arg.get("C") in ("40001", "40P01") {
                return True;
            }
        }
        current = current.__cause__ or current.__context__;
        seen += 1;
    }
    return False;
}

def flush_now {
    # Write pending changes into the request's open transaction, with the ACL check made
    # under the current identity (JI-020). No COMMIT: the request stays atomic.
    # full=True: a field assigned on an EXISTING node isn't in the session's dirty set;
    # only a full flush (hash comparison) sees it. A partial flush would leave it to the
    # end-of-request flush, which runs as the caller and may silently skip it (P2.5).
    # A serialization failure here becomes Jac's WriteConflict, which re-runs the whole
    # request in a fresh transaction; Jac retries only that, and would answer this one
    # with a 500 (JI-031). Our endpoints are safe to re-run: side effects happen in
    # on_commit and claims are released on failure.
    try {
        Jac.get_context().mem.flush(full=True);
    } except Exception as e {
        if not _serialization_failure(e) {
            raise e;
        }
        raise WriteConflict(anchor_id=UUID(node_id(root))) from e;
    }
}

def commit_now {
    # Flush and COMMIT now, under the current identity, so a write conflict surfaces
    # inside the request, where Jac replays it (WriteConflict), instead of at session
    # close, where a failed commit is only logged and the client still gets its answer
    # (JI-038). For write paths that run concurrently (holds, orders). Call last: the
    # request's work after it runs in a new transaction.
    flush_now();
    try {
        commit();
    } except WriteConflict as e {
        raise e;
    } except Exception as e {
        if not _serialization_failure(e) {
            raise e;
        }
        raise WriteConflict(anchor_id=UUID(node_id(root))) from e;
    }
}

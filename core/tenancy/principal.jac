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
"""

import secrets;
import from uuid { UUID, uuid4 }
import from jaclang { JacRuntime as Jac }

glob PRINCIPAL_PREFIX: str = "svc-tenant-";

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

def flush_now {
    # Write pending changes into the request's open transaction, with the ACL check made
    # under the current identity (JI-020). No COMMIT: the request stays atomic.
    # full=True: a field assigned on an EXISTING node isn't in the session's dirty set;
    # only a full flush (hash comparison) sees it. A partial flush would leave it to the
    # end-of-request flush, which runs as the caller and may silently skip it (P2.5).
    Jac.get_context().mem.flush(full=True);
}

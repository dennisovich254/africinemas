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
import from jaclang { JacRuntime as Jac }

def node_id(node_obj: any) -> str {  # jac:ignore[W1037]
    return str(node_obj.__jac__.id);
}

def owner_id(node_obj: any) -> str {  # jac:ignore[W1037]
    return str(getattr(node_obj.__jac__, "root"));
}

def access_level(target: any) -> str {  # jac:ignore[W1037]
    return str(Jac.check_access_level(target.__jac__).name);
}

def new_principal(label: str) -> str {
    # An internal user whose random password is never stored or returned, so nobody
    # can log in as it. Returns the principal's root id.
    ctx = Jac.get_context();
    users = Jac.get_user_manager(ctx.base_path_dir or "");
    created = users.create_internal_user(
        f"svc-tenant-{secrets.token_hex(8)}", secrets.token_urlsafe(32)
    );
    if "error" in created {
        raise RuntimeError(f"could not create the principal for {label}: {created}");
    }
    root_id = users.ensure_user_root(str(created["user_id"]));
    if not root_id {
        raise RuntimeError(f"the principal for {label} has no root");
    }
    return str(root_id);
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
    Jac.get_context().mem.flush();
}

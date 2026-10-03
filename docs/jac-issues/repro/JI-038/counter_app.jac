"""JI-038 minimal reproduction: concurrent increments of one node, nothing else.

No act_as, no claims, no permissions games: one signed-in user, one Counter on their
root. Each bump reads the counter and adds 1. Per the persistence guide, a request
that loses a race is replayed (or answered 409 after conflict_max_attempts), so the
final count must equal the number of bumps answered 200.
"""

node Counter {
    has hits: int = 0;
}

def:priv setup -> bool {
    if not [root-->[?:Counter]] {
        root ++> Counter();
    }
    return True;
}

def:priv bump -> int {
    counter = [root-->[?:Counter]][0];
    counter.hits += 1;
    return counter.hits;
}

def:priv hits -> int {
    return [root-->[?:Counter]][0].hits;
}

# Variant B: the app's pattern. The counter belongs to its owner's root; each bump comes
# from an anonymous caller that switches the request's root to the owner (the runtime
# internal ExecutionContext.set_user_root, as core/tenancy/principal.jac act_as does),
# writes, flushes, and switches back before returning.
import from jaclang { JacRuntime as Jac }

def:priv owner_root -> str {
    return str(Jac.get_context().user_root.id);
}

def:pub bump_as(owner: str) -> int {
    ctx = Jac.get_context();
    me = str(ctx.user_root.id);
    ctx.set_user_root(owner);
    try {
        counter = [root-->[?:Counter]][0];
        counter.hits += 1;
        Jac.get_context().mem.flush(full=True);
        found = counter.hits;
    } finally {
        ctx.set_user_root(me);
    }
    return found;
}

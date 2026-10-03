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

# Variants C and D: the hold path's shape. SEATS small nodes; every request loads all
# of them (as the hold path loads a showtime's seats) and writes a DIFFERENT one, then
# flushes in full. C runs as one signed-in user; D switches to the owner's root.
node Spot {
    has number: int,
        taken: int = 0;
}

def:priv setup_spots(count: int) -> bool {
    if not [root-->[?:Spot]] {
        for n in range(count) {
            root ++> Spot(number=n);
        }
    }
    return True;
}

def _take(n: int) -> bool {
    spots = [root-->[?:Spot]];
    for s in spots {
        if s.number == n {
            s.taken += 1;
        }
    }
    Jac.get_context().mem.flush(full=True);
    return True;
}

def:priv take(n: int) -> bool {
    return _take(n);
}

def:pub take_as(owner: str, n: int) -> bool {
    ctx = Jac.get_context();
    me = str(ctx.user_root.id);
    ctx.set_user_root(owner);
    try {
        done = _take(n);
    } finally {
        ctx.set_user_root(me);
    }
    return done;
}

def:priv taken_count -> int {
    return len(
        [
            s
            for s in [root-->[?:Spot]]
            if s.taken > 0
        ]
    );
}

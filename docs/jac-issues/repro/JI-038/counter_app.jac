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

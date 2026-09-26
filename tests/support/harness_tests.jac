"""P0.3: tests for the test harness itself (two_tenant_world, identity switching, isolation)."""

import from tests.support.harness { two_tenant_world, ACTOR_NAMES }

test "two_tenant_world registers six distinct actors" {
    world = two_tenant_world();
    try {
        assert sorted(world.actors.keys()) == sorted(ACTOR_NAMES) , f"actors: {list(
            world.actors.keys()
        )}";
        user_ids = {a.user_id for a in world.actors.values()};
        root_ids = {a.root_id for a in world.actors.values()};
        assert len(user_ids) == 6 , "every actor needs its own user";
        assert len(root_ids) == 6 , "every actor needs its own root";
        for a in world.actors.values() {
            assert a.token != "" , f"{a.username} has no token";
        }
    } finally {
        world.close();
    }
}

test "as_actor switches the caller identity" {
    world = two_tenant_world();
    try {
        me_a = world.as_actor("owner_a").get("/user/me");
        me_b = world.as_actor("customer_b").get("/user/me");
        assert me_a.status_code == 200 , f"owner_a /user/me: {me_a.status_code} {me_a.text}";
        assert me_b.status_code == 200 , f"customer_b /user/me: {me_b.status_code} {me_b.text}";
        assert world.actors["owner_a"].username in me_a.text;
        assert world.actors["customer_b"].username in me_b.text;
        assert world.actors["owner_a"].username not in me_b.text;
    } finally {
        world.close();
    }
}

test "anonymous caller is unauthenticated" {
    world = two_tenant_world();
    try {
        resp = world.anonymous().get("/user/me");
        assert resp.status_code == 401 , f"expected 401, got {resp.status_code}: {resp.text}";
    } finally {
        world.close();
    }
}

test "each world has an isolated store" {
    first = two_tenant_world();
    second = two_tenant_world();
    try {
        # Same usernames register cleanly in both worlds, so nothing is shared.
        assert first.base_path != second.base_path;
        assert first.actors["owner_a"].user_id != second.actors["owner_a"].user_id;
    } finally {
        first.close();
        second.close();
    }
}

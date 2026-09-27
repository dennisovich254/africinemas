"""Spike S2 (plan P1.2): pass criteria for staff access through group grants.

From docs/architecture.md §138 S2: `allow_group` grants on tenant nodes let staff (via
MemberOf -> StaffGroup) read and write through normal traversal; removing the
membership revokes access immediately; tenant B's staff see nothing. Plus what the
model depends on: nobody can join a group on their own, and it all persists.
"""

import from os { path }
import from uuid { UUID }
import from tests.support.served { Served, served }

glob S2_ENTRY: str = path.join(path.dirname(path.abspath(__file__)), "s2_app.jac"),
     CAST: list[str] = ["owner_a", "staff_a", "owner_b", "staff_b"];

def _uuid(value: str) -> str {
    return str(UUID(value));
}

def _setup -> tuple[Served, dict[str, str], dict[str, str]] {
    # Two tenants, each with one staff member who accepted an invite.
    app = served(S2_ENTRY, CAST);
    a = app.call("owner_a", "s2_create_tenant", {"name": "Nova"});
    b = app.call("owner_b", "s2_create_tenant", {"name": "Imax Rift"});
    for (owner, staff, t) in [("owner_a", "staff_a", a), ("owner_b", "staff_b", b)] {
        token = app.call(owner, "s2_invite", {"tenant_id": t["tenant_id"]});
        assert app.call(staff, "s2_join", {"token": token})["joined"];
    }
    return (app, a, b);
}

test "staff reach their tenant and its venue with write access through the group" {
    (app, a, _) = _setup();
    try {
        view = app.call("staff_a", "s2_staff_view");
        assert view
            == [
                {"tenant": "Nova", "level": "WRITE", "venues": ["Nova Main Hall"]}
            ] , view;
    } finally {
        app.close();
    }
}

test "a staff member's write persists and the owner sees it" {
    (app, _, _) = _setup();
    try {
        assert app.call("staff_a", "s2_rename_venues", {"new_name": "Screen 1"}) == 1;
        assert app.call("owner_a", "s2_owner_venues") == ["Screen 1"];
    } finally {
        app.close();
    }
}

test "joining adds no per-user entry to tenant nodes (one group grant covers all staff)" {
    (app, a, _) = _setup();
    try {
        acl = app.call("owner_a", "s2_acl", {"tenant_id": a["tenant_id"]});
        assert acl["groups"] == [_uuid(a["group_id"])] , acl;
        staff_root = _uuid(app.actors["staff_a"].root_id);
        assert staff_root not in acl["roots"] , acl;
        assert acl["roots"] == [_uuid(app.actors["owner_a"].root_id)] , acl;
    } finally {
        app.close();
    }
}

test "a venue added after joining is visible to existing staff" {
    (app, a, _) = _setup();
    try {
        app.call(
            "owner_a", "s2_add_venue", {"tenant_id": a["tenant_id"], "name": "Rooftop"}
        );
        assert app.call("staff_a", "s2_staff_view")[0]["venues"]
            == ["Nova Main Hall", "Rooftop"];
    } finally {
        app.close();
    }
}

test "removing the membership revokes access on the very next request" {
    (app, a, _) = _setup();
    try {
        removed = app.call(
            "owner_a",
            "s2_remove_staff",
            {
                "tenant_id": a["tenant_id"],
                "staff_root_id": app.actors["staff_a"].root_id
            }
        );
        assert removed == {"removed": 1} , removed;
        assert app.call("staff_a", "s2_staff_view") == [];
        assert app.call("staff_a", "s2_rename_venues", {"new_name": "Hijacked"}) == 0;
        probe = app.call("staff_a", "s2_probe", {"node_id_str": a["tenant_id"]});
        assert probe["can_read"] == False and probe["can_write"] == False , probe;
        assert app.call("owner_a", "s2_owner_venues") == ["Nova Main Hall"];
    } finally {
        app.close();
    }
}

test "removed staff cannot rejoin on their own, and strangers cannot self-join" {
    (app, a, _) = _setup();
    try {
        app.call(
            "owner_a",
            "s2_remove_staff",
            {
                "tenant_id": a["tenant_id"],
                "staff_root_id": app.actors["staff_a"].root_id
            }
        );
        for who in ["staff_a", "staff_b"] {
            app.post(who, "s2_try_self_join", {"group_id": a["group_id"]});
        }
        assert app.call("staff_a", "s2_staff_view") == [];
        assert [v["tenant"] for v in app.call("staff_b", "s2_staff_view")]
            == ["Imax Rift"];
    } finally {
        app.close();
    }
}

test "an invite token works only once" {
    app = served(S2_ENTRY, CAST);
    try {
        a = app.call("owner_a", "s2_create_tenant", {"name": "Nova"});
        token = app.call("owner_a", "s2_invite", {"tenant_id": a["tenant_id"]});
        assert app.call("staff_a", "s2_join", {"token": token})["joined"];
        assert not app.call("staff_b", "s2_join", {"token": token})["joined"];
        assert app.call("staff_b", "s2_staff_view") == [];
    } finally {
        app.close();
    }
}

test "tenant B's staff see nothing of tenant A, even with its ids" {
    (app, a, _) = _setup();
    try {
        assert [v["tenant"] for v in app.call("staff_b", "s2_staff_view")]
            == ["Imax Rift"];
        for node in [a["tenant_id"], a["group_id"]] {
            probe = app.call("staff_b", "s2_probe", {"node_id_str": node});
            assert probe["can_read"] == False and probe["can_write"] == False , probe;
        }
        app.call("staff_b", "s2_rename_venues", {"new_name": "B only"});
        assert app.call("owner_a", "s2_owner_venues") == ["Nova Main Hall"];
        assert app.call("owner_b", "s2_owner_venues") == ["B only"];
    } finally {
        app.close();
    }
}

test "memberships and grants persist across a restart" {
    (app, a, _) = _setup();
    try {
        app.restart();
        view = app.call("staff_a", "s2_staff_view");
        assert view
            == [
                {"tenant": "Nova", "level": "WRITE", "venues": ["Nova Main Hall"]}
            ] , view;
        app.call(
            "owner_a",
            "s2_remove_staff",
            {
                "tenant_id": a["tenant_id"],
                "staff_root_id": app.actors["staff_a"].root_id
            }
        );
        app.restart();
        assert app.call("staff_a", "s2_staff_view") == [] , "the removal persisted too";
    } finally {
        app.close();
    }
}

test "a used invite is consumed on commit: repeats are refused and nothing duplicates" {
    app = served(S2_ENTRY, CAST);
    try {
        a = app.call("owner_a", "s2_create_tenant", {"name": "Nova"});
        token = app.call("owner_a", "s2_invite", {"tenant_id": a["tenant_id"]});
        assert app.call("staff_a", "s2_join", {"token": token})["joined"];
        # The token was consumed on commit, so a repeat is refused, not duplicated.
        again = app.call("staff_a", "s2_join", {"token": token});
        assert not again["joined"] , again;
        assert not app.call("staff_b", "s2_join", {"token": token})["joined"] , "single use";
        assert len(app.call("staff_a", "s2_staff_view")) == 1 , "no duplicate membership";
    } finally {
        app.close();
    }
}

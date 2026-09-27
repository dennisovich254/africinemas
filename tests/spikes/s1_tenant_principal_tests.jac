"""Spike S1 (plan P1.1): pass criteria for per-tenant service-principal ownership.

From docs/architecture.md §138 S1: a server-side flow, running on behalf of the
signed-up owner, creates a per-tenant service principal and nodes owned by it.
Plus what that ownership is for (§4 layer 1): the owner gets access by grant, other
tenants get nothing, and the owner's access can be taken away.
"""

import shutil;
import tempfile;
import from os { path }
import from uuid { UUID }
import from jaclang.testing.testing { JacTestClient }
import from tests.support.harness { TEST_PASSWORD, register_actor, Actor }

def _uuid(value: str) -> str {
    # Registration returns root ids as bare hex; anchors print dashed UUIDs.
    return str(UUID(value));
}

glob S1_ENTRY: str = path.join(path.dirname(path.abspath(__file__)), "s1_app.jac");

obj Spike {
    has client: JacTestClient,
        base_path: str,
        actors: dict[str, Actor] = {};

    def call(actor: str, name: str, body: dict[str, any] | None = None) -> any {  # jac:ignore[W1037]
        self.client.set_auth_token(self.actors[actor].token);
        resp = self.client.post(f"/function/{name}", json=body or {});
        assert resp.status_code == 200 , f"{actor} {name}: {resp.status_code} {resp.text}";
        return resp.data["result"];
    }

    def close {
        self.client.close();
        shutil.rmtree(self.base_path, ignore_errors=True);
    }
}

def _spike -> Spike {
    base = tempfile.mkdtemp(prefix="africinemas-s1-");
    spike = Spike(
        client=JacTestClient.from_file(S1_ENTRY, base_path=base), base_path=base
    );
    for name in ["owner_a", "owner_b"] {
        spike.actors[name] = register_actor(spike.client, name);
    }
    return spike;
}

test "tenant nodes are owned by the tenant's service principal, not the owner" {
    s = _spike();
    try {
        a = s.call("owner_a", "s1_create_tenant", {"name": "Nova"});
        assert _uuid(a["caller_root_id"]) == _uuid(s.actors["owner_a"].root_id);
        assert _uuid(a["principal_root_id"]) != _uuid(a["caller_root_id"]);
        assert _uuid(a["tenant_owner_id"]) == _uuid(a["principal_root_id"]) , a;
        assert _uuid(a["venue_owner_id"]) == _uuid(a["principal_root_id"]) , a;
    } finally {
        s.close();
    }
}

test "every tenant gets its own principal" {
    s = _spike();
    try {
        a = s.call("owner_a", "s1_create_tenant", {"name": "Nova"});
        b = s.call("owner_b", "s1_create_tenant", {"name": "Imax Rift"});
        assert _uuid(a["principal_root_id"]) != _uuid(b["principal_root_id"]);
    } finally {
        s.close();
    }
}

test "the owner reaches their tenant with write access by grant" {
    s = _spike();
    try {
        s.call("owner_a", "s1_create_tenant", {"name": "Nova"});
        mine = s.call("owner_a", "s1_my_tenants");
        assert len(mine) == 1 , mine;
        assert mine[0]["name"] == "Nova";
        assert mine[0]["level"] == "WRITE" , mine;
        assert mine[0]["venues"] == ["Nova Main Hall"] , "the grant reaches the venue too";
    } finally {
        s.close();
    }
}

test "another tenant's owner can neither read nor write it, even with its id" {
    s = _spike();
    try {
        a = s.call("owner_a", "s1_create_tenant", {"name": "Nova"});
        s.call("owner_b", "s1_create_tenant", {"name": "Imax Rift"});
        assert [t["name"] for t in s.call("owner_b", "s1_my_tenants")] == ["Imax Rift"];
        probe = s.call("owner_b", "s1_probe", {"tenant_id": a["tenant_id"]});
        assert probe["can_read"] == False and probe["can_write"] == False , probe;
        # A write or an edge attempted with the leaked id must not stick.
        s.client.set_auth_token(s.actors["owner_b"].token);
        s.client.post("/function/s1_try_tamper", json={"tenant_id": a["tenant_id"]});
        assert [t["name"] for t in s.call("owner_a", "s1_my_tenants")] == ["Nova"];
        assert [t["name"] for t in s.call("owner_b", "s1_my_tenants")] == ["Imax Rift"];
    } finally {
        s.close();
    }
}

test "the owner's access can be revoked, because they don't own the nodes" {
    s = _spike();
    try {
        a = s.call("owner_a", "s1_create_tenant", {"name": "Nova"});
        s.call("owner_a", "s1_step_down", {"tenant_id": a["tenant_id"]});
        probe = s.call("owner_a", "s1_probe", {"tenant_id": a["tenant_id"]});
        assert probe["can_read"] == False and probe["can_write"] == False , probe;
        assert [t["name"] for t in s.call("owner_a", "s1_my_tenants")] == [] , "the tenant drops out of the owner's traversal";
    } finally {
        s.close();
    }
}

test "the principal cannot be used to log in" {
    s = _spike();
    try {
        a = s.call("owner_a", "s1_create_tenant", {"name": "Nova"});
        s.client.clear_auth();
        for guess in [TEST_PASSWORD, "", a["principal_root_id"]] {
            resp = s.client.login(f"svc-tenant-{a['principal_root_id'][:16]}", guess);
            assert not resp.ok , "no known credential logs in as a principal";
        }
    } finally {
        s.close();
    }
}

test "the tenant subgraph persists under the principal's root across a restart" {
    s = _spike();
    try {
        a = s.call("owner_a", "s1_create_tenant", {"name": "Nova"});
        assert s.call(
            "owner_a",
            "s1_principal_view",
            {"principal_root_id": a["principal_root_id"]}
        )
            == ["Nova"];
        # Restart: a fresh app on the same store; nothing may live only in memory.
        s.client.close();
        s.client = JacTestClient.from_file(S1_ENTRY, base_path=s.base_path);
        login = s.client.login("owner_a", TEST_PASSWORD);
        assert login.ok , login.text;
        s.actors["owner_a"].token = str(login.data["token"]);
        mine = s.call("owner_a", "s1_my_tenants");
        assert [(t["name"], t["level"], t["venues"]) for t in mine]
            == [("Nova", "WRITE", ["Nova Main Hall"])] , mine;
        assert s.call(
            "owner_a",
            "s1_principal_view",
            {"principal_root_id": a["principal_root_id"]}
        )
            == ["Nova"];
    } finally {
        s.close();
    }
}

test "after the owner steps down the tenant stays persisted under its principal" {
    s = _spike();
    try {
        a = s.call("owner_a", "s1_create_tenant", {"name": "Nova"});
        s.call("owner_a", "s1_step_down", {"tenant_id": a["tenant_id"]});
        assert s.call(
            "owner_a",
            "s1_principal_view",
            {"principal_root_id": a["principal_root_id"]}
        )
            == ["Nova"] , "no orphaned data";
    } finally {
        s.close();
    }
}

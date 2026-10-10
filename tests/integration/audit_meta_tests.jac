"""P7.2: every endpoint records exactly what the registry says in the audit log.

Against the production app (main.jac). The owner of Nova calls every endpoint in the
isolation registry with its probe aimed at Nova itself, then reads Nova's audit log: an
endpoint whose `audit` is an action adds exactly one event of that action (most probes
are refused, and a refused attempt is recorded too); every other endpoint adds none.
Ending the shift goes last: reading the log needs one (ADR-0006).

Endpoints that work without a cinema (accept_invite, create_cinema) record in the
cinema they join or make; tests/integration/audit_tests.jac covers those with real
calls.
"""

import json;
import os;
import shutil;
import tempfile;
import from uuid { UUID }
import from jaclang.testing.testing { JacTestClient }
import from tests.support.harness { register_actor }
import from tests.isolation.registry { REGISTRY }

glob MAIN: str = os.path.join(
         os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
         "main.jac"
     );

def _call(client: JacTestClient, token: str, name: str, body: dict[str, any]) -> any {  # jac:ignore[W1037]
    client.set_auth_token(token);
    resp = client.post(f"/function/{name}", json=body);
    assert resp.status_code == 200 , f"{name}: {resp.status_code} {resp.text[:300]}";
    return resp.data["result"];
}

def _log(client: JacTestClient, token: str, slug: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The cinema's audit events, newest first.
    got = _call(
        client,
        token,
        "audit_log",
        {"tenant": slug, "before": "", "limit": 100, "action": ""}
    );
    assert got["ok"] , got;
    return got["events"];
}

def _newer(events: list[dict[str, any]], last: str) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The events newer than the one with id `last`.
    ids = [e["event_id"] for e in events];
    return events[:ids.index(last)] if last in ids else events;
}

test "every endpoint records exactly its registry action, or nothing" {
    base = tempfile.mkdtemp(prefix="africinemas-audit-");
    client = JacTestClient.from_file(MAIN, base_path=base);
    try {
        a = register_actor(client, "owner_a");
        b = register_actor(client, "owner_b");
        _call(
            client, a.token, "create_cinema", {"name": "Nova Cinemas", "slug": "nova"}
        );
        _call(
            client, b.token, "create_cinema", {"name": "Imax Rift", "slug": "imax-rift"}
        );
        assert _call(client, a.token, "start_shift", {"tenant": "nova"})["ok"];
        assert _call(client, b.token, "start_shift", {"tenant": "imax-rift"})["ok"];
        events = _log(client, a.token, "nova");
        assert [e["action"] for e in events] == ["shift.started", "cinema.created"];
        last = events[0]["event_id"];
        order = sorted(
            REGISTRY.keys(),
            key=lambda (n: str) -> tuple[bool, str] { return (n == "end_shift", n); }
        );
        for name in order {
            spec = REGISTRY[name];
            assert "audit" in spec , f"{name}: say in the registry what it audits";
            scope = spec["scope"];
            if scope in ["webhook", "mcp", "oauth"] or name == "create_cinema" {
                continue;
            }
            body = json.loads(
                json.dumps(spec.get("probe", {})).replace("{tenant}", "nova")
            );
            token = "" if scope == "storefront" else a.token;
            _call(client, token, name, body);
            if name == "end_shift" {
                assert _call(client, a.token, "start_shift", {"tenant": "nova"})["ok"];
            }
            events = _log(client, a.token, "nova");
            added = _newer(events, last);
            if name == "end_shift" {
                # end_shift, then the start_shift that lets the log be read.
                assert [e["action"] for e in added]
                    == ["shift.started", "shift.ended"] , f"{name}: {added}";
            } elif spec["audit"] and scope == "tenant" {
                assert len(added) == 1 , f"{name}: {len(added)} events: {added}";
                assert added[0]["action"] == spec["audit"] , f"{name}: {added[0]}";
                assert UUID(added[0]["actor_id"]) == UUID(a.root_id) , added[0];
                assert added[0]["result"] not in ["", "pending"] , f"{name}: {added[
                    0
                ]}";
            } else {
                assert added == [] , f"{name} recorded {added}";
            }
            last = events[0]["event_id"];
        }
        # Nothing A did reached B's log.
        assert [e["action"] for e in _log(client, b.token, "imax-rift")]
            == ["shift.started", "cinema.created"];
    } finally {
        client.close();
        shutil.rmtree(base, ignore_errors=True);
    }
}

test "attempts at another cinema are recorded in neither cinema's log" {
    base = tempfile.mkdtemp(prefix="africinemas-audit-");
    client = JacTestClient.from_file(MAIN, base_path=base);
    try {
        a = register_actor(client, "owner_a");
        b = register_actor(client, "owner_b");
        _call(
            client, a.token, "create_cinema", {"name": "Nova Cinemas", "slug": "nova"}
        );
        _call(
            client, b.token, "create_cinema", {"name": "Imax Rift", "slug": "imax-rift"}
        );
        assert _call(client, a.token, "start_shift", {"tenant": "nova"})["ok"];
        assert _call(client, b.token, "start_shift", {"tenant": "imax-rift"})["ok"];
        before_a = _log(client, a.token, "nova");
        before_b = _log(client, b.token, "imax-rift");
        for (name, spec) in REGISTRY.items() {
            if spec["scope"] == "tenant" and spec["audit"] and name != "end_shift" {
                body = json.loads(
                    json.dumps(spec["probe"]).replace("{tenant}", "imax-rift")
                );
                assert _call(client, a.token, name, body)["ok"] == False , name;
            }
        }
        assert _log(client, a.token, "nova") == before_a;
        assert _log(client, b.token, "imax-rift") == before_b;
        # And B's log can't be read by A.
        assert _call(
            client,
            a.token,
            "audit_log",
            {"tenant": "imax-rift", "before": "", "limit": 10, "action": ""}
        )["error"]["code"]
            == "not_found";
    } finally {
        client.close();
        shutil.rmtree(base, ignore_errors=True);
    }
}

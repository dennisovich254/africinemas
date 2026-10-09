"""Tenant isolation (plan §2.3), run against the production app (main.jac).

1. The registry must list exactly the endpoints the app serves.
2. Every "tenant" endpoint, called by tenant A's owner with tenant B's selector, is
   refused with the same answer as an unknown cinema, and leaks nothing of B.
3. "caller" endpoints never show A anything of B.
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
     ),
     NOT_FOUND: dict[str, bool | dict[str, str]] = {
         "ok": False,
         "error": {"code": "not_found", "message": "No such cinema."}
     };

def _served_endpoints(client: JacTestClient) -> set[str] {
    spec = client.get("/openapi.json");
    assert spec.status_code == 200 , f"openapi: {spec.status_code}";
    names: set[str] = set();
    for route in json.loads(spec.text)["paths"].keys() {
        for prefix in ["/function/", "/walker/"] {
            name = route[len(prefix):].split("/")[0]
                if route.startswith(prefix)
                else "";
            # Skip the generic templated routes ("/function/{name}"); keep real names.
            if name and "{" not in name {
                names.add(name);
            }
        }
        # Endpoints on custom paths (@restspec): M-Pesa's callback (P5.4), MCP (P8.2, P8.3).
        if route.startswith("/hooks/") or route.endswith("/mcp") {
            names.add(f"route:{route}");
        }
    }
    return names;
}

def _norm(root_id: str) -> str {
    return str(UUID(root_id));
}

def _call(client: JacTestClient, token: str, name: str, body: dict[str, any]) -> any {  # jac:ignore[W1037]
    client.set_auth_token(token);
    resp = client.post(f"/function/{name}", json=body);
    assert resp.status_code == 200 , f"{name}: {resp.status_code} {resp.text[:300]}";
    return resp.data["result"];
}

test "the isolation registry lists exactly the endpoints the app serves" {
    base = tempfile.mkdtemp(prefix="africinemas-iso-");
    client = JacTestClient.from_file(MAIN, base_path=base);
    try {
        served = _served_endpoints(client);
        assert served , "found no endpoints: is /openapi.json still available in tests?";
        missing = sorted(served - set(REGISTRY.keys()));
        stale = sorted(set(REGISTRY.keys()) - served);
        assert missing == [] , f"add these to tests/isolation/registry.jac: {missing}";
        assert stale == [] , f"remove these from the registry: {stale}";
    } finally {
        client.close();
        shutil.rmtree(base, ignore_errors=True);
    }
}

test "every tenant endpoint refuses another tenant's selector and leaks nothing" {
    base = tempfile.mkdtemp(prefix="africinemas-iso-");
    client = JacTestClient.from_file(MAIN, base_path=base);
    try {
        a = register_actor(client, "owner_a");
        b = register_actor(client, "owner_b");
        made_a = _call(
            client, a.token, "create_cinema", {"name": "Nova Cinemas", "slug": "nova"}
        );
        made_b = _call(
            client, b.token, "create_cinema", {"name": "Imax Rift", "slug": "imax-rift"}
        );
        for (name, spec) in REGISTRY.items() {
            if spec["scope"] == "tenant" {
                body = json.loads(
                    json.dumps(spec["probe"]).replace("{tenant}", "imax-rift")
                );
                answer = _call(client, a.token, name, body);
                assert answer == NOT_FOUND , f"{name}: A reached B: {answer}";
            } elif spec["scope"] == "customer" {
                body = json.loads(
                    json.dumps(spec["probe"]).replace("{tenant}", "imax-rift")
                );
                answer = json.dumps(_call(client, a.token, name, body));
                assert b.root_id not in answer and _norm(b.root_id) not in answer , f"{name} leaked B's owner: {answer}";
            } elif spec["scope"] == "storefront" {
                body = json.loads(
                    json.dumps(spec["probe"]).replace("{tenant}", "imax-rift")
                );
                answer = json.dumps(_call(client, "", name, body));
                for secret in [b.root_id, _norm(b.root_id), made_b["tenant_id"]] {
                    assert secret not in answer , f"{name} leaked B's internals: {answer}";
                }
            } elif spec["scope"] in ["webhook", "mcp"] {
                # A cinema's own MCP connector is tenant A's ("nova"), asked about B.
                path = name[len("route:"):].replace(
                    "{token}", "probe-token-xxxxxxxxxxxx"
                ).replace(
                    "{slug}", "nova"
                );
                body = json.loads(
                    json.dumps(spec["probe"]).replace("{tenant}", "imax-rift")
                );
                client.set_auth_token("");
                resp = client.post(path, json=body);
                assert resp.status_code == 200 , f"{name}: {resp.status_code}";
                for secret in [b.root_id, _norm(b.root_id), made_b["tenant_id"]] {
                    assert secret not in resp.text , f"{name} leaked B's internals";
                }
            } elif spec["scope"] == "caller" and name != "create_cinema" {
                answer = json.dumps(
                    _call(client, a.token, name, spec.get("probe", {}))
                );
                assert made_b["tenant_id"] not in answer
                    and "imax-rift" not in answer , f"{name} leaked B: {answer}";
                assert made_a["tenant_id"] in answer or name != "my_cinemas";
            }
        }
        still_b = _call(client, b.token, "my_access", {"tenant": "imax-rift"});
        assert still_b["name"] == "Imax Rift" , "a probe changed tenant B";
    } finally {
        client.close();
        shutil.rmtree(base, ignore_errors=True);
    }
}

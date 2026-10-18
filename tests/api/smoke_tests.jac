"""P0.2 smoke tests: the served web app boots and exposes its first endpoint."""

import json;
import os;
import shutil;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

glob REPO_ROOT: str = os.path.dirname(
         os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
     );

glob _BASES: dict[int, str] = {};

def _client -> JacTestClient {
    # Each test app gets a fresh temp folder (and database); _close removes the folder,
    # which lets scripts/test.sh prune the database afterwards.
    base = tempfile.mkdtemp(prefix="africinemas-smoke-");
    client = JacTestClient.from_file(
        os.path.join(REPO_ROOT, "main.jac"), base_path=base
    );
    _BASES[id(client)] = base;
    return client;
}

def _close(client: JacTestClient) {
    client.close();
    shutil.rmtree(_BASES.pop(id(client), ""), ignore_errors=True);
}

test "app_info endpoint returns the app identity" {
    client = _client();
    try {
        resp = client.post("/function/app_info", json={});
        assert resp.status_code == 200 , f"status {resp.status_code}: {resp.text}";
        info = resp.data["result"];
        assert info["name"] == "africinemas" , f"unexpected payload {info}";
        assert info["version"] != "" , "version must be set";
    } finally {
        _close(client);
    }
}

test "built-in health probe answers" {
    client = _client();
    try {
        resp = client.get("/healthz");
        assert resp.status_code == 200 , f"status {resp.status_code}: {resp.text}";
    } finally {
        _close(client);
    }
}

test "the production app serves cinema signup, and only to signed-in users" {
    client = _client();
    try {
        for name in ["create_cinema", "my_cinemas"] {
            resp = client.post(
                f"/function/{name}", json={"name": "Nova", "slug": "nova"}
            );
            assert resp.status_code == 401 , f"{name}: {resp.status_code} {resp.text[:200]}";
        }
    } finally {
        _close(client);
    }
}

test "staff invitations require a signed-in caller and jobs stay private" {
    client = _client();
    try {
        resp = client.post("/function/accept_invite", json={"token": "invalid"});
        assert resp.status_code == 401 , f"accept_invite: {resp.status_code}";
        spec = client.get("/openapi.json");
        assert spec.status_code == 200 , f"openapi: {spec.status_code}";
        paths = json.loads(spec.text)["paths"];
        for name in [
            "sweep_holds",
            "send_ticket_mail",
            "resolve_payments",
            "settle_callbacks"
        ] {
            assert f"/function/{name}" not in paths , f"internal job {name} is advertised";
            resp = client.post(f"/function/{name}", json={});
            # A missing route may reach the SPA fallback and reject POST with 405.
            assert resp.status_code in [404, 405] , f"internal job {name}: {resp.status_code}";
        }
    } finally {
        _close(client);
    }
}

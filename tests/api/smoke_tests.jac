"""P0.2 smoke tests: the served web app boots and exposes its first endpoint."""

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

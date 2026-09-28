"""P0.2 smoke tests: the served web app boots and exposes its first endpoint."""

import os;
import tempfile;
import from jaclang.testing.testing { JacTestClient }

glob REPO_ROOT: str = os.path.dirname(
         os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
     );

def _client -> JacTestClient {
    return JacTestClient.from_file(
        os.path.join(REPO_ROOT, "main.jac"), base_path=tempfile.mkdtemp()
    );
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
        client.close();
    }
}

test "built-in health probe answers" {
    client = _client();
    try {
        resp = client.get("/healthz");
        assert resp.status_code == 200 , f"status {resp.status_code}: {resp.text}";
    } finally {
        client.close();
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
        client.close();
    }
}

"""Production hardening, verified against a REAL server over HTTP (P0.7 fix, JI-014).

Why a real server: the running server ignores profile overrides for [serve] settings, while
the config API applies them. Testing the config API passed while production was not
actually hardened. So this test boots the app exactly as production would (a copy of the
repo, deploy/production.env, secrets from the environment) and probes it over HTTP.

The copy lives in a temp folder, so the server gets its own fresh embedded-Postgres
database (databases are keyed by project path). The test drops that database afterwards.
"""

import http.client;
import json;
import os;
import shutil;
import socket;
import subprocess;
import tempfile;
import time;
import urllib.error;
import urllib.request;
import from pathlib { Path }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     COPY_SKIP: list[str] = [
         ".git",
         ".jac",
         "node_modules",
         "resources",
         ".claude",
         "storage"
     ],
     FAKE_SECRET: str = "test-only-signing-secret-0123456789abcdef",
     BOOT_TIMEOUT_S: int = 240;

def _free_port -> int {
    with socket.socket() as s {
        s.bind(("127.0.0.1", 0));
        return s.getsockname()[1];
    }
}

def _read_env_file(path: Path) -> dict[str, str] {
    values: dict[str, str] = {};
    for raw in path.read_text().splitlines() {
        line = raw.strip();
        if line and not line.startswith("#") and "=" in line {
            (key, value) = line.split("=", 1);
            values[key.strip()] = value.strip();
        }
    }
    return values;
}

def _request(method: str, url: str, body: bytes | None = None) -> tuple[int, str] {
    req = urllib.request.Request(
        url, data=body, method=method, headers={"Content-Type": "application/json"}
    );
    try {
        with urllib.request.urlopen(req, timeout=60) as resp {
            return (resp.status, resp.read().decode("utf-8", "replace"));
        }
    } except urllib.error.HTTPError as e {
        return (e.code, e.read().decode("utf-8", "replace"));
    }
}

def _status_for_declared_body(port: int, path: str, size: int) -> int {
    # Declares a large body in Content-Length and reads the server's answer before sending it.
    # A server with a body limit rejects on the header alone (413). Without one, it waits for
    # the body that never comes: that timeout is reported as 0 ("not rejected").
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=15);
    try {
        conn.putrequest("POST", path);
        conn.putheader("Content-Type", "application/json");
        conn.putheader("Content-Length", str(size));
        conn.endheaders();
        return conn.getresponse().status;
    } except TimeoutError {
        return 0;
    } finally {
        conn.close();
    }
}

def _drop_database_owned_by(workdir: str) {
    listing = subprocess.run(
        ["jac", "db", "list"], capture_output=True, text=True, timeout=120
    ).stdout;
    for line in listing.splitlines() {
        cols = line.split();
        if cols and cols[-1] == workdir and cols[0].startswith("jac_") {
            subprocess.run(
                ["jac", "db", "drop", cols[0], "--yes"],
                capture_output=True,
                timeout=120
            );
        }
    }
}

test "production server is hardened over HTTP" {
    assert shutil.which("jac") , "jac must be on PATH";
    workdir = tempfile.mkdtemp(prefix="africinemas-prod-");
    shutil.copytree(
        REPO_ROOT,
        workdir,
        dirs_exist_ok=True,
        ignore=shutil.ignore_patterns(*COPY_SKIP)
    );
    # The project's Python environment (its [dependencies], such as Pillow), shared
    # rather than copied, as the other real-server tests do.
    os.mkdir(os.path.join(workdir, ".jac"));
    os.symlink(REPO_ROOT / ".jac" / "venv", os.path.join(workdir, ".jac", "venv"));
    port = _free_port();
    env = {
        ** os.environ,
        ** _read_env_file(REPO_ROOT / "deploy" / "production.env"),
        "JAC_SERVE_AUTH_SECRET": FAKE_SECRET
    };
    log_path = os.path.join(workdir, "server.log");
    log = open(log_path, "w");
    server = subprocess.Popen(
        ["jac", "run", "--no-client", "--port", str(port)],
        cwd=workdir,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=log,
        stderr=subprocess.STDOUT
    );
    base = f"http://127.0.0.1:{port}";
    try {
        deadline = time.time() + BOOT_TIMEOUT_S;
        up = False;
        while time.time() < deadline and not up {
            if server.poll() is not None {
                break;
            }
            try {
                up = _request("GET", f"{base}/healthz")[0] == 200;
            } except OSError {
                time.sleep(2);
            }
        }
        assert up , f"server did not start; log:\n{open(log_path).read()[-3000:]}";

        # Public API docs and the graph browser must not be reachable.
        for path in ["/docs", "/openapi.json", "/graph"] {
            (status, _) = _request("GET", f"{base}{path}");
            assert status == 404 , f"{path} returned {status} in production";
        }

        # Request bodies over 5 MB are rejected.
        status = _status_for_declared_body(port, "/function/app_info", 6 * 1024 * 1024);
        assert status == 413 , f"6 MB body was not rejected (status {status}; 0 means the server waited for the body, so there is no size limit)";

        # Jac's built-in admin (admin / "changeme") must not exist.
        login = json.dumps(
            {
                "identity": {"type": "username", "value": "admin"},
                "credential": {"type": "password", "password": "changeme"}
            }
        ).encode();
        (status, text) = _request("POST", f"{base}/user/login", login);
        assert not (status == 200 and '"ok": true' in text) , "admin / changeme can log in";

        # The app still works.
        (status, text) = _request("POST", f"{base}/function/app_info", b"{}");
        assert status == 200 and "africinemas" in text , f"app_info: {status} {text[:200]}";
    } finally {
        server.terminate();
        try {
            server.wait(timeout=30);
        } except subprocess.TimeoutExpired {
            server.kill();
        }
        log.close();
        _drop_database_owned_by(workdir);
        shutil.rmtree(workdir, ignore_errors=True);
    }
}

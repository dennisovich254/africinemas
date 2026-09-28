"""Spikes S3 and S6 (plan P1.4), checked against a real `jac run` server.

S3 (architecture §138): can `_before_request` middleware see the Host header, pass a
resolved value on, or reject a request? S6: can the staff token lifetime go below one
day? Both answers on Jac 0.37.18 are "no", so ADR-0006 adopts the fallbacks. These
tests pin the observed behaviour: if one starts failing after a Jac upgrade, revisit
ADR-0006.
"""

import base64;
import json;
import os;
import shutil;
import tempfile;
import from pathlib { Path }
import from tests.support.real_server { RealServer, http_call, remove_project }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     SPIKE_TOML: str = """[project]
name = "s3-spike"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-s3-");
    shutil.copy(
        REPO_ROOT / "tests" / "spikes" / "s3_app.jac", Path(workdir) / "main.jac"
    );
    (Path(workdir) / "jac.toml").write_text(SPIKE_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

def _lifetime_s(token: str) -> float {
    part = token.split(".")[1];
    claims = json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)));
    return float(claims["exp"]) - float(claims["iat"]);
}

test "S3: the documented _before_request hook never runs, and is a public route" {
    workdir = _project();
    hook_log = Path(workdir) / "hook_hits.txt";
    server = RealServer(
        workdir=workdir, env={** os.environ, "S3_HOOK_LOG": str(hook_log)}
    );
    try {
        server.start();
        token = server.register("staff_a");
        base = server.base();
        # A function and a walker, anonymous and signed in, with a tenant-style Host.
        for (path, tok) in [
            ("/function/s3_hello", ""),
            ("/walker/s3_ping", ""),
            ("/walker/s3_ping", token),
            ("/function/s3_whoami", token)
        ] {
            (status, _) = http_call("POST", f"{base}{path}", {}, tok);
            assert status == 200 , f"{path}: {status}";
        }
        assert not hook_log.exists() , f"the hook ran: {hook_log.read_text()[:300]}";
        # The hook walker is exposed like any walker, and fails when called.
        (status, payload) = http_call("POST", f"{base}/walker/_before_request", {});
        assert status >= 400 or "error" in str(payload) , (status, payload);
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

test "S6: token lifetime is whole days only, so staff tokens can't be shorter than 24 h" {
    workdir = _project();
    try {
        # 1 day: a 24 h token that works.
        server = RealServer(
            workdir=workdir, env={** os.environ, "JAC_SERVE_AUTH_TOKEN_TTL_DAYS": "1"}
        );
        server.start();
        token = server.register("staff_a");
        assert _lifetime_s(token) == 86400.0 , _lifetime_s(token);
        assert server.call("s3_whoami", {}, token);
        server.stop();

        # Half a day: the server refuses to start.
        server = RealServer(
            workdir=workdir, env={** os.environ, "JAC_SERVE_AUTH_TOKEN_TTL_DAYS": "0.5"}
        );
        refused = False;
        try {
            server.start();
        } except RuntimeError as e {
            refused = "must be an integer" in str(e);
        }
        server.stop();
        assert refused , "a fractional token lifetime was accepted";

        # Zero: tokens expire as they are issued and are refused.
        server = RealServer(
            workdir=workdir, env={** os.environ, "JAC_SERVE_AUTH_TOKEN_TTL_DAYS": "0"}
        );
        server.start();
        token = server.login("staff_a");
        assert _lifetime_s(token) == 0.0;
        (status, payload) = http_call(
            "POST", f"{server.base()}/function/s3_whoami", {}, token
        );
        assert status == 401 , (status, payload);
        server.stop(drop=True);
    } finally {
        remove_project(workdir);
    }
}

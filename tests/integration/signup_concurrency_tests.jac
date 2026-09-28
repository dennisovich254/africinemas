"""P2.2: owners racing to sign up with the same slug (real server).

Exactly one cinema is created; every other owner is told `slug_taken`, and no loser
leaves a tenant or a principal behind.
"""

import os;
import shutil;
import tempfile;
import from concurrent.futures { ThreadPoolExecutor }
import from pathlib { Path }
import from tests.support.real_server { RealServer, remove_project }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     RACERS: int = 6,
     APP_TOML: str = """[project]
name = "signup-race"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[placement]
default = "server"
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-signup-");
    shutil.copy(
        REPO_ROOT / "tests" / "apps" / "signup_app.jac", Path(workdir) / "main.jac"
    );
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "owners racing for one slug: exactly one cinema, the rest are told slug_taken" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        tokens = [server.register(f"owner_{i}") for i in range(RACERS)];
        principals_before = server.call("t_principals");
        attempt = lambda (token: str) -> any { return server.call(
            "create_cinema", {"name": "Nova Cinemas", "slug": "nova"}, token
        ); };
        with ThreadPoolExecutor(max_workers=RACERS) as pool {
            results = list(pool.map(attempt, tokens));
        }
        created = [
            r
            for r in results
            if r["created"]
        ];
        assert len(created) == 1 , results;
        assert all(
            r["error"]["code"] == "slug_taken"
            for r in results
            if not r["created"]
        ) , results;
        assert server.call("t_tenants", {"slug": "nova"}) == 1;
        assert server.call("t_slug_holder", {"slug": "nova"})
            == created[0]["tenant_id"];
        assert server.call("t_principals") == principals_before + 1 , "losers left principals";
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

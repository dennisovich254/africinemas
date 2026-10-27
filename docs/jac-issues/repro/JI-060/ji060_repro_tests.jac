"""JI-060: an omitted endpoint parameter arrives as the text of its default.

Boots main.jac (this folder) on a real server and calls `probe` twice: with only the
required parameter, then with every parameter. Run from the repo root:

    jac test docs/jac-issues/repro/JI-060/ji060_repro_tests.jac -v

Expected: both calls see real values (bool False, float 0.0). On Jac 0.38.0 the first
test fails: the omitted `flag` arrives as the string "False" (so `if flag` is true) and
`n` as the string "0.0". The second test passes.

Without the test harness, the same in a shell (from this folder):

    jac run --port 8000 -w 1
    curl -s -X POST localhost:8000/function/probe \
         -H 'content-type: application/json' -d '{"a": "x"}'
"""

import os;
import shutil;
import tempfile;
import from pathlib { Path }
import from tests.support.real_server { RealServer }

glob HERE: Path = Path(__file__).resolve().parent,
     REPO_ROOT: Path = Path(__file__).resolve().parents[4];

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="ji060-");
    shutil.copy(HERE / "main.jac", Path(workdir) / "main.jac");
    shutil.copy(HERE / "jac.toml", Path(workdir) / "jac.toml");
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

def _probe(server: RealServer, body: dict[str, any]) -> dict[str, str] {  # jac:ignore[W1037]
    return server.call("probe", body);
}

test "omitted parameters get their typed defaults" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        omitted = _probe(server, {"a": "x"});
        print("omitted:", omitted);
        assert omitted["flag"] == "bool:False" , omitted;
        assert omitted["n"] == "float:0.0" , omitted;
        assert omitted["branch"] == "flag is false" , omitted;
        sent = _probe(server, {"a": "x", "flag": False, "n": 0.0, "s": ""});
        print("sent:", sent);
        assert sent["flag"] == "bool:False"
            and sent["branch"] == "flag is false" , sent;
    } finally {
        server.stop();
        shutil.rmtree(workdir, ignore_errors=True);
    }
}

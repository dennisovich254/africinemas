"""Spike S7 (plan P3.5b): pass criteria for the public storefront projection (§4).

Against a real server (outside one, root.shared is just the caller's root):
1. A cinema principal can hang a Storefront off root.shared; with grant(READ) anyone,
   anonymous or logged in, can read it by id, and it is owned by the principal.
2. Anonymous callers can't change it or attach nodes under it.
3. Anyone can attach nodes to root.shared itself, so public reads must reach a
   Storefront by the id its cinema recorded, never by searching root.shared.
"""

import os;
import shutil;
import tempfile;
import from pathlib { Path }
import from tests.support.real_server { RealServer, remove_project }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     APP_TOML: str = """[project]
name = "s7-storefront"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[placement]
default = "server"
""",
     APP_MAIN: str = """import from s7_app {
    s7_publish,  # jac:ignore[W2037]
    s7_read,
    s7_tamper,
    s7_attach,
    s7_impostor,
    s7_count_shared
}
""";

def _project -> str {
    workdir = tempfile.mkdtemp(prefix="africinemas-s7-");
    (Path(workdir) / "main.jac").write_text(APP_MAIN);
    shutil.copy(
        REPO_ROOT / "tests" / "spikes" / "s7_app.jac", Path(workdir) / "s7_app.jac"
    );
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(APP_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "a cinema's storefront on root.shared is readable by all and changeable by none" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        staff = server.register("staff");
        other = server.register("other");
        published = server.call("s7_publish", {"name": "Nova"}, staff);
        storefront = published["storefront_id"];
        assert published["owner"].replace("-", "")
            == published["principal"].replace("-", "") , published;
        # 1. Readable by anyone, anonymous or logged in.
        anonymous = server.call("s7_read", {"storefront_id": storefront});
        assert anonymous["found"]
            and anonymous["name"] == "Nova"
            and anonymous["items"] == ["Rafiki 19:30"] , anonymous;
        assert anonymous["reader_root"] == published["shared_root"] , "anonymous runs on root.shared";
        logged_in = server.call("s7_read", {"storefront_id": storefront}, other);
        assert logged_in["found"]
            and logged_in["items"] == ["Rafiki 19:30"] , logged_in;
        # 2. Not changeable: a field write and an attached node don't stick.
        for name in ["s7_tamper", "s7_attach"] {
            try {
                server.call(name, {"storefront_id": storefront});
            } except AssertionError {
                # Refused outright is fine too.
            }
        }
        after = server.call("s7_read", {"storefront_id": storefront});
        assert after["name"] == "Nova" and after["items"] == ["Rafiki 19:30"] , after;
        # 3. root.shared itself takes anyone's nodes: search it and you find impostors.
        server.call("s7_impostor", {"name": "Nova"});
        shared = server.call("s7_count_shared", {});
        assert shared["names"].count("Nova") == 2 , shared;
        assert server.call("s7_read", {"storefront_id": storefront})["items"]
            == ["Rafiki 19:30"] , "by id, the real one";
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

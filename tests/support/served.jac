"""A served test app with named, logged-in actors that can be restarted on the same store.

Used by the platform spikes (tests/spikes). `restart()` closes the app and opens a new
one on the same base_path, then logs every actor back in: anything that only lived in
memory is gone, so assertions after it prove persistence.

"""

import shutil;
import tempfile;
import from jaclang.testing.testing { JacTestClient }
import from tests.support.harness { TEST_PASSWORD, Actor, register_actor }

obj Served {
    has app_file: str,
        client: JacTestClient,
        base_path: str,
        actors: dict[str, Actor] = {};

    def call(actor: str, name: str, body: dict[str, any] | None = None) -> any {  # jac:ignore[W1037]
        resp = self.post(actor, name, body);
        assert resp.status_code == 200 , f"{actor} {name}: {resp.status_code} {resp.text}";
        return resp.data["result"];
    }

    def post(actor: str, name: str, body: dict[str, any] | None = None) -> any {  # jac:ignore[W1037]
        self.client.set_auth_token(self.actors[actor].token);
        return self.client.post(f"/function/{name}", json=body or {});
    }

    def restart {
        self.client.close();
        self.client = JacTestClient.from_file(self.app_file, base_path=self.base_path);
        for (name, actor) in self.actors.items() {
            login = self.client.login(name, TEST_PASSWORD);
            assert login.ok , f"re-login {name}: {login.text}";
            actor.token = str(login.data["token"]);
        }
    }

    def close {
        self.client.close();
        shutil.rmtree(self.base_path, ignore_errors=True);
    }
}

def served(app_file: str, actor_names: list[str]) -> Served {
    base = tempfile.mkdtemp(prefix="africinemas-spike-");
    app = Served(
        app_file=app_file,
        client=JacTestClient.from_file(app_file, base_path=base),
        base_path=base
    );
    try {
        for name in actor_names {
            app.actors[name] = register_actor(app.client, name);
        }
    } except Exception as e {
        app.close();
        raise e;
    }
    return app;
}

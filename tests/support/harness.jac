"""Shared test harness: isolated app instances and a two-tenant cast of actors.

Every World gets its own temp store (base_path), so tests never share graph
state. P0.3 registers six user accounts; P2.2 extends two_tenant_world() to
provision tenants A and B and attach these actors as owner/staff/customer.
"""

import shutil;
import tempfile;
import from os { path }
import from jaclang.testing.testing { JacTestClient }

glob REPO_ROOT: str = path.dirname(
         path.dirname(path.dirname(path.abspath(__file__)))
     ),
     ENTRY: str = path.join(REPO_ROOT, "main.jac"),
     TEST_PASSWORD: str = "Test-Passw0rd!",
     ACTOR_NAMES: list[str] = [
         "owner_a",
         "staff_a",
         "customer_a",
         "owner_b",
         "staff_b",
         "customer_b"
     ];

obj Actor {
    has username: str,
        user_id: str,
        root_id: str,
        token: str;
}

obj World {
    has client: JacTestClient,
        base_path: str,
        actors: dict[str, Actor] = {};

    def as_actor(name: str) -> JacTestClient {
        self.client.set_auth_token(self.actors[name].token);
        return self.client;
    }

    def anonymous -> JacTestClient {
        self.client.clear_auth();
        return self.client;
    }

    def close {
        self.client.close();
        shutil.rmtree(self.base_path, ignore_errors=True);
    }
}

def new_app -> tuple[JacTestClient, str] {
    base = tempfile.mkdtemp(prefix="africinemas-test-");
    return (JacTestClient.from_file(ENTRY, base_path=base), base);
}

def register_actor(client: JacTestClient, username: str) -> Actor {
    resp = client.register_user(username, TEST_PASSWORD);
    if not resp.ok {
        raise RuntimeError(
            f"register {username} failed: {resp.status_code} {resp.text}"
        );
    }
    data = resp.data;
    return Actor(
        username=username,
        user_id=str(data["user_id"]),
        root_id=str(data["root_id"]),
        token=str(data["token"])
    );
}

def two_tenant_world -> World {
    (client, base) = new_app();
    world = World(client=client, base_path=base);
    try {
        for name in ACTOR_NAMES {
            world.actors[name] = register_actor(client, name);
        }
        client.clear_auth();
    } except Exception as e {
        world.close();
        raise e;
    }
    return world;
}

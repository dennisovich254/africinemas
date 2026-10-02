"""Boot a real `jac run` server from a temp project and talk to it over HTTP.

For behaviour that only exists in a served process (the scheduler, production [serve]
settings). Each server gets its own embedded-Postgres database, keyed by the project
path; `stop(drop=True)` drops it, so test runs don't leave databases behind.
"""

import json;
import os;
import shutil;
import socket;
import subprocess;
import time;
import urllib.error;
import urllib.request;
import from datetime { datetime, timedelta, timezone }

glob BOOT_TIMEOUT_S: int = 240;

def free_port -> int {
    with socket.socket() as s {
        s.bind(("127.0.0.1", 0));
        return s.getsockname()[1];
    }
}

def http_call(
    method: str, url: str, body: dict[str, any] | None = None, token: str = ""
) -> tuple[int, any] {  # jac:ignore[W1037]
    headers = {"Content-Type": "application/json"};
    if token {
        headers["Authorization"] = f"Bearer {token}";
    }
    data = json.dumps(body).encode() if body is not None else None;
    req = urllib.request.Request(url, data=data, method=method, headers=headers);
    try {
        with urllib.request.urlopen(req, timeout=60) as resp {
            return (resp.status, json.loads(resp.read().decode() or "null"));
        }
    } except urllib.error.HTTPError as e {
        raw = e.read().decode("utf-8", "replace");
        try {
            return (e.code, json.loads(raw));
        } except ValueError {
            return (e.code, raw);
        }
    }
}

obj RealServer {
    has workdir: str,
        env: dict[str, str],
        port: int = 0,
        proc: any = None,  # jac:ignore[W1037]
        log_path: str = "";

    def base -> str {
        return f"http://127.0.0.1:{self.port}";
    }

    def start {
        self.port = free_port();
        self.log_path = os.path.join(self.workdir, f"server-{self.port}.log");
        log = open(self.log_path, "w");
        self.proc = subprocess.Popen(
            ["jac", "run", "--port", str(self.port)],
            cwd=self.workdir,
            env=self.env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT
        );
        deadline = time.time() + BOOT_TIMEOUT_S;
        while time.time() < deadline {
            if self.proc.poll() is not None {
                break;
            }
            try {
                if http_call("GET", f"{self.base()}/healthz")[0] == 200 {
                    return;
                }
            } except OSError {
                time.sleep(2);
            }
        }
        raise RuntimeError(f"server did not start; log:\n{self.log()[-3000:]}");
    }

    def log -> str {
        return open(self.log_path).read() if self.log_path else "";
    }

    def call(name: str, body: dict[str, any] | None = None, token: str = "") -> any {  # jac:ignore[W1037]
        (status, payload) = http_call(
            "POST", f"{self.base()}/function/{name}", body or {}, token
        );
        assert status == 200 , f"{name}: {status} {payload}";
        return payload["data"]["result"];
    }

    def register(username: str, password: str = "Test-Passw0rd!") -> str {
        (status, payload) = http_call(
            "POST",
            f"{self.base()}/user/register",
            {
                "identities": [{"type": "username", "value": username}],
                "credential": {"type": "password", "password": password}
            }
        );
        assert status in [200, 201] , f"register {username}: {status} {payload}";
        return str(payload["data"]["token"]);
    }

    def login(username: str, password: str = "Test-Passw0rd!") -> str {
        (status, payload) = http_call(
            "POST",
            f"{self.base()}/user/login",
            {
                "identity": {"type": "username", "value": username},
                "credential": {"type": "password", "password": password}
            }
        );
        assert status == 200 , f"login {username}: {status} {payload}";
        return str(payload["data"]["token"]);
    }

    def stop(drop: bool = False) {
        if self.proc is not None and self.proc.poll() is None {
            self.proc.terminate();
            try {
                self.proc.wait(timeout=30);
            } except subprocess.TimeoutExpired {
                self.proc.kill();
                self.proc.wait(timeout=30);
            }
        }
        self.proc = None;
        if drop {
            drop_database_of(self.workdir);
        }
    }
}

def wait_until(check: any, timeout_s: float = 30.0, every_s: float = 0.5) -> bool {  # jac:ignore[W1037]
    deadline = time.time() + timeout_s;
    while time.time() < deadline {
        if check() {
            return True;
        }
        time.sleep(every_s);
    }
    return False;
}

def drop_database_of(workdir: str) {
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

def remove_project(workdir: str) {
    shutil.rmtree(workdir, ignore_errors=True);
}

def published_showtime(server: RealServer) -> str {
    # Cinema "nova" with a published three-seat showtime (A1-A3) in two days; returns
    # the showtime's id. The server must serve the endpoints it calls.
    owner = server.register("owner");
    server.call("create_cinema", {"name": "Nova Cinemas", "slug": "nova"}, owner);
    server.call("start_shift", {"tenant": "nova"}, owner);
    venue = server.call(
        "create_venue",
        {"tenant": "nova", "name": "Westgate", "city": "", "address": ""},
        owner
    )["venue"]["venue_id"];
    screen = server.call(
        "create_auditorium",
        {"tenant": "nova", "venue_id": venue, "name": "Screen 1"},
        owner
    )["auditorium"]["auditorium_id"];
    server.call(
        "save_layout",
        {
            "tenant": "nova",
            "auditorium_id": screen,
            "rows": 1,
            "cols": 3,
            "seats": [{"label": f"A{i + 1}", "row": 0, "col": i} for i in range(3)]
        },
        owner
    );
    server.call("publish_layout", {"tenant": "nova", "auditorium_id": screen}, owner);
    movie = server.call(
        "create_movie",
        {
            "tenant": "nova",
            "title": "Rafiki",
            "synopsis": "",
            "runtime_minutes": 90,
            "age_rating": "18",
            "genres": [],
            "language": ""
        },
        owner
    )["movie"]["movie_id"];
    start = (datetime.now(timezone.utc) + timedelta(days=2)).replace(microsecond=0);
    screening = server.call(
        "create_screening",
        {
            "tenant": "nova",
            "auditorium_id": screen,
            "movie_id": movie,
            "starts_at": start.isoformat()
        },
        owner
    )["screening"]["screening_id"];
    for step in ["schedule_screening", "publish_screening"] {
        assert server.call(step, {"tenant": "nova", "screening_id": screening}, owner)[
            "ok"
        ];
    }
    return screening;
}

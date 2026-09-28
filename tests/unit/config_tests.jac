"""P0.7: configuration profiles, checked through the server's own settings loader.

These are fast unit checks. The authoritative check is
tests/integration/production_server_tests.jac, which probes a REAL server over HTTP,
because the running server ignores profile overrides for [serve] (JI-014).
Production [serve] hardening therefore lives in deploy/production.env (JAC_SERVE_* env vars).
Secrets come only from the environment, never `${VAR}` placeholders in jac.toml (JI-015).
"""

import os;
import re;
import from pathlib { Path }
import from jaclang.project.config { JacConfig }
import from jaclang.server.settings { ServeSettings }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     PROD_ENV_FILE: Path = REPO_ROOT / "deploy" / "production.env",
     FAKE_SECRET: str = "test-only-signing-secret-0123456789abcdef",
     FIVE_MB: int = 5 * 1024 * 1024,
     PROFILES: list[str] = ["development", "test", "production"];

def _resolve(profile: str) -> JacConfig {
    cfg = JacConfig.resolve(REPO_ROOT, profile=profile);
    assert cfg is not None , f"no jac.toml found from {REPO_ROOT}";
    return cfg;
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

def _swap_env(values: dict[str, str | None]) -> dict[str, str | None] {
    previous: dict[str, str | None] = {};
    for (k, v) in values.items() {
        previous[k] = os.environ.get(k);
        if v is None {
            os.environ.pop(k, None);
        } else {
            os.environ[k] = v;
        }
    }
    return previous;
}

test "production server settings are hardened" {
    assert PROD_ENV_FILE.exists() , f"missing {PROD_ENV_FILE}";
    env = {** _read_env_file(PROD_ENV_FILE), "JAC_SERVE_AUTH_SECRET": FAKE_SECRET};
    previous = _swap_env(env);
    try {
        s = ServeSettings.load(config=_resolve("production"));
        assert s.docs_enabled == False , "/docs and /openapi.json must be off in production";
        assert s.graph_enabled == False , "/graph must be off in production";
        assert s.auth.secret == FAKE_SECRET , "JWT secret must come from JAC_SERVE_AUTH_SECRET";
        assert s.auth.token_ttl_days <= 1 , f"tokens live {s.auth.token_ttl_days} days";
        assert s.limits.max_body_bytes <= FIVE_MB , f"max body {s.limits.max_body_bytes} bytes";
    } finally {
        _swap_env(previous);
    }
}

test "every profile loads through the server's settings loader" {
    # JI-014: a profile overriding a nested [serve.*] table also crashes ServeSettings.load.
    for profile in PROFILES {
        ServeSettings.load(config=_resolve(profile));
    }
}

test "production disables Jac's built-in admin bootstrap" {
    # Otherwise it creates admin / "changeme" on first start (ADR-0001).
    admin = _resolve("production").get_plugin_config("scale").get("admin", {});
    assert admin.get("enabled") == False , f"scale.admin in production: {admin}";
}

test "jac.toml has no required-env placeholders" {
    # JI-015: ${VAR} and ${VAR:?msg} keep their literal text when unset, so a secret
    # placeholder would silently become a published string. Only ${VAR:-default} is safe.
    text = (REPO_ROOT / "jac.toml").read_text();
    bad = re.findall(r"\$\{[A-Za-z_][A-Za-z0-9_]*(?::\?[^}]*)?\}", text);
    assert not bad , f"unsafe placeholders in jac.toml: {bad}";
}

test "production.env holds settings, not secrets" {
    for name in _read_env_file(PROD_ENV_FILE).keys() {
        upper = name.upper();
        assert not any(
            w in upper
            for w in ["SECRET", "PASSWORD", "TOKEN_KEY", "API_KEY", "PASSKEY"]
        ) , f"{name} looks like a secret; set it in the deployment environment instead";
    }
}

test "development runs without any production secrets" {
    previous = _swap_env({"JAC_SERVE_AUTH_SECRET": None});
    try {
        s = ServeSettings.load(config=_resolve("development"));
        assert s.docs_enabled == True , "docs stay on for local development";
    } finally {
        _swap_env(previous);
    }
}

test "jac.toml has no production [serve] overrides" {
    # JI-014: the running server ignores them, so they would give false confidence.
    text = (REPO_ROOT / "jac.toml").read_text();
    assert re.search(r"^\[environments\.[A-Za-z0-9_-]+\.serve[\].]", text, re.M)
        is None , "put [serve] settings in deploy/production.env as JAC_SERVE_* env vars";
}

test "production never enables test-only switches" {
    # Fault injection (core/faults.jac) and clock control (core/clock.jac) are for tests.
    prod = _read_env_file(PROD_ENV_FILE);
    for name in ["AFRICINEMAS_FAULTS", "AFRICINEMAS_CLOCK_CONTROL"] {
        assert name not in prod , f"{name} must never be set in production";
    }
}

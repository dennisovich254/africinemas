"""Set up data for browser tests through the public API, as a real client would.

The e2e server keeps its data between runs, so every account and cinema made here gets
a random suffix (`unique`) and an `e2e-` prefix.
"""

import os;
import from pathlib { Path }
import json;
import time;
import uuid;
import from tests.support.real_server { http_call }
import from e2e.support.web { BASE_URL }

glob PASSWORD: str = "correct-horse-42";

def unique(prefix: str) -> str {
    return f"e2e-{prefix}-{uuid.uuid4().hex[:8]}";
}

def email_for(name: str) -> str {
    return f"{name}@example.com";
}

def register(email: str) -> str {
    # Signs up with an email identity (as the web form does) and returns a session token.
    (status, body) = http_call(
        "POST",
        f"{BASE_URL}/user/register",
        {
            "identities": [{"type": "email", "value": email}],
            "credential": {"type": "password", "password": PASSWORD}
        }
    );
    assert status in (200, 201) , f"register {email}: {status} {body}";
    (status, body) = http_call(
        "POST",
        f"{BASE_URL}/user/login",
        {
            "identity": {"type": "email", "value": email},
            "credential": {"type": "password", "password": PASSWORD}
        }
    );
    assert status == 200 , f"login {email}: {status} {body}";
    token = str(body["data"]["token"]);
    # Staff confirm their email before creating a cinema (P14.2), the real way.
    confirm_email_of(email, token);
    return token;
}

def outbox_link(to: str, marker: str) -> str {
    # The last link containing `marker` in an email to `to` in the test server's outbox
    # (scripts/e2e_env.sh: its mail job runs every 2 seconds), waiting for it to arrive.
    import from email { message_from_string }
    folder = Path(os.environ.get("AFRICINEMAS_OUTBOX_DIR", "e2e/artifacts/outbox"));
    for _ in range(60) {
        found = "";
        for f in (sorted(folder.glob("*.eml")) if folder.exists() else []) {
            message = message_from_string(f.read_text(errors="replace"));
            if to not in str(message["To"] or "") {
                continue;
            }
            for part in message.walk() {
                if part.get_content_type() == "text/plain" {
                    raw: any = part.get_payload(decode=True);  # jac:ignore[W1037]
                    text = bytes(raw).decode(errors="replace");
                    for word in text.split() {
                        if marker in word {
                            found = word;
                        }
                    }
                }
            }
        }
        if found {
            return found;
        }
        time.sleep(0.5);
    }
    raise AssertionError(f"no email to {to} with {marker}");
}

def confirm_email_of(email: str, token: str) {
    # Asks for the link, then follows it, as the owner would.
    sent = call(token, "send_email_check", {"email": email});
    assert sent["ok"] , sent;
    if sent["confirmed"] {
        return;
    }
    link = outbox_link(email, "/verify-email#");
    confirmed = call("", "confirm_email", {"token": link.split("#", 1)[1]});
    assert confirmed["ok"] , confirmed;
}

def platform_name(email: str) -> str {
    # A platform account's username (core/platform/accounts.jac).
    return "platform:" + email.strip().lower().replace("@", ":");
}

def platform_login(email: str) -> int {
    (status, _) = platform_session(email);
    return status;
}

def platform_session(email: str) -> tuple[int, str] {
    # (the login's status, its token) for the platform account of `email`.
    (status, body) = http_call(
        "POST",
        f"{BASE_URL}/user/login",
        {
            "identity": {"type": "username", "value": platform_name(email)},
            "credential": {"type": "password", "password": PASSWORD}
        }
    );
    token = str(body["data"]["token"]) if status == 200 else "";
    return (status, token);
}

def platform_admin -> str {
    # The browser tests' platform super admin (AFRICINEMAS_PLATFORM_ADMINS in
    # scripts/e2e_env.sh): joined the first time from the link the server writes to
    # AFRICINEMAS_PLATFORM_SETUP_FILE (core/platform/setup_file.jac), with PASSWORD.
    # Its email, to sign in with on the platform's /sign-in (PLATFORM_URL).
    email = os.environ.get(
        "AFRICINEMAS_PLATFORM_ADMINS", "platform-admin@example.com"
    ).split(
        ","
    )[0].strip();
    if platform_login(email) == 200 {
        return email;
    }
    path = os.environ.get("AFRICINEMAS_PLATFORM_SETUP_FILE", "");
    for _ in range(60) {
        if path and os.path.exists(path) {
            break;
        }
        time.sleep(0.5);
    }
    with open(path) as f {
        links = json.loads(f.read());
    }
    joined = call("", "platform_join", {"token": links[email], "password": PASSWORD});
    assert joined["ok"] , f"platform_join: {joined}";
    return email;
}

def call(token: str, name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
    # An endpoint's own answer (the `result` inside the transport envelope).
    (status, body) = http_call("POST", f"{BASE_URL}/function/{name}", args, token);
    assert status == 200 , f"{name}: {status} {body}";
    return body["data"]["result"];
}

def go_live(slug: str) {
    # Makes a cinema public the real way (P14.1): the platform's super admin approves it.
    (_, token) = platform_session(platform_admin());
    approved = call(token, "platform_approve_cinema", {"slug": slug});
    assert approved["ok"] , approved;
}

def owner_with_cinema(name: str = "Nova Cinemas", live: bool = True) -> dict[str, str] {
    # A signed-up owner with one cinema and an open shift.
    email = email_for(unique("owner"));
    token = register(email);
    slug = unique("cinema");
    created = call(
        token, "create_cinema", {"name": name, "slug": slug, "email": email}
    );
    assert created["created"] , created;
    if live {
        go_live(slug);
    }
    assert call(token, "start_shift", {"tenant": slug})["ok"];
    return {"email": email, "token": token, "slug": slug, "name": name};
}

def add_venue(owner: dict[str, str], name: str = "Westgate") -> str {
    # A venue of the owner's cinema; returns its id.
    answer = call(
        owner["token"],
        "create_venue",
        {"tenant": owner["slug"], "name": name, "city": "Nairobi", "address": ""}
    );
    assert answer["ok"] , answer;
    return answer["venue"]["venue_id"];
}

def add_screen(owner: dict[str, str], venue_id: str, name: str = "Screen 1") -> str {
    # A screen (auditorium) at the venue; returns its id.
    answer = call(
        owner["token"],
        "create_auditorium",
        {"tenant": owner["slug"], "venue_id": venue_id, "name": name}
    );
    assert answer["ok"] , answer;
    return answer["auditorium"]["auditorium_id"];
}

def add_staff(owner: dict[str, str], role: str, venue_id: str = "") -> dict[str, str] {
    # Invites a new person with `role` and has them accept; returns their credentials.
    invite = call(
        owner["token"],
        "invite_staff",
        {"tenant": owner["slug"], "role": role, "venue_id": venue_id}
    );
    assert invite["ok"] , invite;
    email = email_for(unique(role));
    token = register(email);
    accepted = call(token, "accept_invite", {"token": invite["token"], "email": email});
    assert accepted["ok"] , accepted;
    return {"email": email, "token": token};
}

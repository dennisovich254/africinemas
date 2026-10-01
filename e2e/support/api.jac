"""Set up data for browser tests through the public API, as a real client would.

The e2e server keeps its data between runs, so every account and cinema made here gets
a random suffix (`unique`) and an `e2e-` prefix.
"""

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
    return str(body["data"]["token"]);
}

def call(token: str, name: str, args: dict[str, any]) -> any {  # jac:ignore[W1037]
    # An endpoint's own answer (the `result` inside the transport envelope).
    (status, body) = http_call("POST", f"{BASE_URL}/function/{name}", args, token);
    assert status == 200 , f"{name}: {status} {body}";
    return body["data"]["result"];
}

def owner_with_cinema(name: str = "Nova Cinemas") -> dict[str, str] {
    # A signed-up owner with one cinema and an open shift.
    email = email_for(unique("owner"));
    token = register(email);
    slug = unique("cinema");
    created = call(
        token, "create_cinema", {"name": name, "slug": slug, "email": email}
    );
    assert created["created"] , created;
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

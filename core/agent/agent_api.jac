"""The AI booking agent's endpoints: agent_chat (P8.1) and a cinema's own storefront chat,
cinema_chat (P8.4).

agent_chat(message, history, holder) answers anyone: browsing needs no login; a
signed-in customer's own bookings need theirs (the tools check). `holder` is the
conversation's random holder id, kept by the client like the storefront's (it owns
the seats the conversation holds); it's checked like the storefront's.

The client sends the conversation back each time, so it's untrusted: only plain user
and assistant turns with text are kept (a forged "system" turn, a tool result or an
injected tool call is dropped), each cut to MESSAGE_MAX, the last HISTORY_MAX of them.
"""

import os;
import time;
import from core.catalog.answers { answer }
import from core.booking.hold_api { check_holder }
import from core.tenancy.open_cinema { open_cinema }
import from core.tenancy.principal { node_id }
import from core.tenancy.responses { NOT_FOUND }
import from core.agent.agent { agent_reply, cinema_reply, MESSAGE_MAX, HISTORY_MAX }

glob ROLES: list[str] = ["user", "assistant"],
     # A storefront chat (P8.4) answers this many of a customer's messages, then points
     # to the website: every message is a paid model call.
     CHAT_TURNS_MAX: int = 20,
     PER_MINUTE_ENV: str = "AFRICINEMAS_CHAT_PER_MINUTE",
     PER_MINUTE_DEFAULT: int = 30,
     # Model calls per cinema in the last minute, on this server (one replica's view).
     _recent: dict[str, list[float]] = {};

def clean_history(history: list[any]) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # The client's conversation, keeping plain user and assistant text turns only.
    kept: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for turn in history if isinstance(history, list) else [] {
        if not isinstance(turn, dict) {
            continue;
        }
        role = turn.get("role");
        content = turn.get("content");
        if role in ROLES and isinstance(content, str) and content.strip() {
            kept.append({"role": role, "content": content[:MESSAGE_MAX]});
        }
    }
    return kept[-HISTORY_MAX:];
}

def _agent_chat(
    message: str,
    history: list[any],  # jac:ignore[W1037]
    holder: str
) -> dict[str, any] {  # jac:ignore[W1037]
    check_holder(holder);
    return agent_reply(message, clean_history(history), holder);
}

def:pub agent_chat(
    message: str,
    history: list[any],  # jac:ignore[W1037]
    holder: str
) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _agent_chat(message, history, holder); });  # jac:ignore[W1037]
}

def _per_minute -> int {
    try {
        return max(1, int(os.environ.get(PER_MINUTE_ENV, "") or PER_MINUTE_DEFAULT));
    } except ValueError {
        return PER_MINUTE_DEFAULT;
    }
}

def _busy(key: str) -> bool {
    # True when cinema `key` has had its share of model calls in the last minute;
    # otherwise counts this one.
    now = time.monotonic();
    window = [
        t
        for t in _recent.get(key, [])
        if now - t < 60
    ];
    if len(window) >= _per_minute() {
        _recent[key] = window;
        return True;
    }
    window.append(now);
    _recent[key] = window;
    return False;
}

def _customer_turns(history: list[any]) -> int {  # jac:ignore[W1037]
    return len(
        [
            t
            for t in (history if isinstance(history, list) else [])
            if isinstance(t, dict) and t.get("role") == "user"
        ]
    );
}

def _cinema_chat(
    slug: str,
    message: str,
    history: list[any],  # jac:ignore[W1037]
    holder: str
) -> dict[str, any] {  # jac:ignore[W1037]
    cinema = open_cinema(slug);
    if cinema is None {
        return NOT_FOUND;
    }
    check_holder(holder);
    site = f"{cinema.name}'s website";
    if _customer_turns(history) >= CHAT_TURNS_MAX {
        return {
            "ok": True,
            "reply": f"That's a long conversation! To carry on, browse showtimes and book on {site}.",
            "cards": []
        };
    }
    if message.strip() and _busy(node_id(cinema)) {
        return {
            "ok": True,
            "reply": f"I'm busy right now. You can browse showtimes and book on {site}, or ask me again in a minute.",
            "cards": []
        };
    }
    return cinema_reply(
        message, clean_history(history), holder, cinema.slug, cinema.name
    );
}

def:pub cinema_chat(
    slug: str,
    message: str,
    history: list[any],  # jac:ignore[W1037]
    holder: str
) -> dict[str, any] {  # jac:ignore[W1037]
    # A cinema's own chat on its storefront (P8.4): anyone may ask, as on the storefront.
    return answer(
        lambda -> any { return _cinema_chat(slug, message, history, holder); }  # jac:ignore[W1037]
    );
}

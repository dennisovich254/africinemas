"""The AI booking agent's endpoint (P8.1), for the chats (MCP Apps 8.3, the storefront 8.5).

agent_chat(message, history, holder) answers anyone: browsing needs no login; a
signed-in customer's own bookings need theirs (the tools check). `holder` is the
conversation's random holder id, kept by the client like the storefront's (it owns
the seats the conversation holds); it's checked like the storefront's.

The client sends the conversation back each time, so it's untrusted: only plain user
and assistant turns with text are kept (a forged "system" turn, a tool result or an
injected tool call is dropped), each cut to MESSAGE_MAX, the last HISTORY_MAX of them.
"""

import from core.catalog.answers { answer }
import from core.booking.hold_api { check_holder }
import from core.agent.agent { agent_reply, MESSAGE_MAX, HISTORY_MAX }

glob ROLES: list[str] = ["user", "assistant"];

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

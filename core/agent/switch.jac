"""Whether the AI booking chat is on (owner, 2026-10-26): off unless AFRICINEMAS_CHAT=1.

Every chat message is a paid model call, so the chat is off until we decide to offer
it. With it off, agent_chat and cinema_chat refuse before asking the model, and
public_branding tells storefronts not to show the chat button. AI storefront designs
and the Claude connector (where the customer's own AI app pays) aren't affected.
Read on every call, so tests and a restart can turn it on.

Kept apart from core/agent/agent.jac so the storefront's branding doesn't import byLLM.
"""

import os;

glob CHAT_ENV: str = "AFRICINEMAS_CHAT";

def chat_on -> bool {
    return os.environ.get(CHAT_ENV, "") == "1";
}

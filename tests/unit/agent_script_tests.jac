"""P8.4: the browser tests' scripted model (core/agent/agent.jac, SCRIPT_ENV).

Only a readable script makes the storefront chat answer from it; without the setting
(as in production) or with an unreadable file, the real model stays.
"""

import os;
import json;
import tempfile;
import from jaclang.byllm.lib { MockLLM }
import from core.agent.agent { _scripted, SCRIPT_ENV }

test "only a readable script replaces the model" {
    os.environ.pop(SCRIPT_ENV, None);
    assert _scripted() is None;
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f {
        json.dump([{"tool": "whats_on", "args": {"cinema": "x", "day": ""}}, "Hi."], f);
        path = f.name;
    }
    try {
        os.environ[SCRIPT_ENV] = path;
        assert isinstance(_scripted(), MockLLM);
        os.environ[SCRIPT_ENV] = path + ".missing";
        assert _scripted() is None;
    } finally {
        os.environ.pop(SCRIPT_ENV, None);
        os.remove(path);
    }
}

test "every model call has a time limit, and the default model is Claude" {
    # byLLM sets no timeout on a plain model call, so litellm's own default (minutes)
    # applied: one chat message took 4 minutes (P8.4). The agent caps every call.
    import sys;
    import core.agent.agent as agent;
    # Read through sys.modules: a Jac import of litellm takes minutes to check.
    assert 0
        < float(sys.modules["litellm"].request_timeout)
        <= agent.CALL_TIMEOUT
        <= 40;
    # Claude for every AI feature (ADR-0049).
    assert agent.DEFAULT_MODEL == "anthropic/claude-opus-5-5";
}

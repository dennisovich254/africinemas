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

"""P16.2: every background job checks in, and the console knows what it does.

Reads every @schedule job in core/: each is in jobs.KNOWN (so the overview and the
alerts can name it) and calls ran() with its own name first thing. A job added later
fails here until it does both.
"""

import os;
import re;
import from core.platform.jobs { KNOWN }

glob ROOT: str = os.path.dirname(
         os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
     ),
     JOB: str = '@schedule\\(trigger=ScheduleTrigger\\.STATIC, interval=\\w+\\)\\ndef (\\w+) \\{\\n\\s+ran\\("(\\w+)"';

test "every scheduled job is known and checks in under its own name" {
    found: dict[str, str] = {};
    defined = 0;
    for (folder, _, names) in os.walk(os.path.join(ROOT, "core")) {
        for name in names {
            if not name.endswith(".jac") {
                continue;
            }
            with open(os.path.join(folder, name), encoding="utf-8") as f {
                text = f.read();
            }
            defined += len(re.findall("\\n@schedule\\(", "\\n" + text));
            for (job, said) in re.findall(JOB, text) {
                assert job == said , f"{job} checks in as {said}";
                found[job] = name;
            }
        }
    }
    assert len(found) == defined , f"{defined} jobs, {len(found)} check in first thing";
    assert sorted(found.keys()) == sorted(KNOWN.keys()) , (
        sorted(found.keys()),
        sorted(KNOWN.keys())
    );
}

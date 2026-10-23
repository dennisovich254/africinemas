"""The browser tests' way to the settings' super admins' join links (P13.1b.a).

scripts/platform_setup.jac prints them on the server, but the browser tests' server
has a database of its own that the script can't reach. When AFRICINEMAS_PLATFORM_SETUP_FILE
names a file (scripts/e2e_env.sh only), this job writes a join link for each super
admin in the server's settings to it, once, as {email: token}; like the email outbox,
it's only on the server's disk. Unset, as everywhere but the tests, it does nothing.
"""

import os;
import json;
import from core.platform.accounts { join_link, SETUP_TTL_S }
import from core.platform.staff_api { allowlisted }

glob SETUP_FILE_ENV: str = "AFRICINEMAS_PLATFORM_SETUP_FILE",
     SETUP_FILE_SECONDS: int = 2 if os.environ.get(SETUP_FILE_ENV, "") else 3600;

@schedule(trigger=ScheduleTrigger.STATIC, interval=SETUP_FILE_SECONDS)
def write_setup_links {
    path = os.environ.get(SETUP_FILE_ENV, "");
    if not path or os.path.exists(path) {
        return;
    }
    links = {email: join_link(email, SETUP_TTL_S) for email in allowlisted()};
    with open(path, "w") as f {
        f.write(json.dumps(links));
    }
}

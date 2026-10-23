"""Join links for the platform's super admins (P13.1b.a); run by scripts/platform_setup.sh.

The super admins in AFRICINEMAS_PLATFORM_ADMINS have no invitation: this prints a link
for each, valid 24 hours, that sets their platform account's password (making the
account the first time, or replacing a forgotten password). Each new link replaces the
last. Only someone who can run commands on the server sees them.
"""

import from core.platform.accounts { join_link, SETUP_TTL_S }
import from core.site { platform_address }
import from core.platform.staff_api { allowlisted }

with entry {
    base = platform_address();
    emails = allowlisted();
    if not emails {
        print("No super admins: set AFRICINEMAS_PLATFORM_ADMINS in .env first.");
    }
    for email in emails {
        token = join_link(email, SETUP_TTL_S);
        print(f"{email}: {base}/join#{token}");
    }
    if emails {
        print(
            f"Each link works once, for {SETUP_TTL_S // 3600} hours. Don't share them."
        );
    }
}

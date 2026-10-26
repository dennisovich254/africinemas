"""`/app/:slug/profile`: Your profile (P12.15, ADR-0077), for every member of staff.

The email they sign in with, the name their colleagues see (on the door list and
sales), and changing their password. The email can't be changed here yet (JI-058), and
a new password doesn't sign out their other devices (JI-059), so the page says to sign
out there.
"""

import from react { useState, useEffect }
import from ...components.ui.spinner { Spinner }
import from core.accounts.profile { my_profile }  # jac:ignore[W2037] authenticated endpoint
import from ..auth.session { signed_in_email }
import from ..auth.ProfileForms { NameForm, PasswordForm }

def:pub ProfileSection(slug: str) -> JsxElement {
    [mine, set_mine] = useState(None);
    [failed, set_failed] = useState(False);
    email = signed_in_email();

    async def load {
        got: any = None;  # jac:ignore[W1037]
        try {
            got = await my_profile(email);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("my_profile failed", e);
        }
        if got is None or not got["ok"] {
            set_failed(True);
            return;
        }
        set_mine(got);
    }

    def start {
        load();
    }
    useEffect(start, [slug]);

    if failed {
        return
            <p role="alert" className="text-sm text-destructive">
                We couldn't load your profile. Refresh the page to try again.
            </p>;
    }
    found: dict[str, any] | None = mine;  # jac:ignore[W1037]
    if found is None {
        return <Spinner aria-label="Loading your profile"/>;
    }
    sign_in: str = found["sign_in"];
    return
        <section data-testid="profile" className="flex max-w-xl flex-col gap-8">
            <div className="flex flex-col gap-1">
                <h2 className="text-lg font-semibold">Signing in</h2>
                <p className="text-sm" data-testid="profile-email">
                    {f"You sign in as {sign_in}."
                        if sign_in
                        else "Sign out and back in to see the email you sign in with."}
                </p>
                <p className="text-sm text-muted-foreground">
                    The email can't be changed yet.
                </p>
            </div>
            <div className="flex flex-col gap-3">
                <h2 className="text-lg font-semibold">Your name</h2>
                <p className="text-sm text-muted-foreground">
                    Your colleagues see it on sales and the door list.
                </p>
                <NameForm name={found["name"]}/>
            </div>
            {sign_in
                and <div className="flex flex-col gap-3">
                    <h2 className="text-lg font-semibold">Your password</h2>
                    <p className="text-sm text-muted-foreground">
                        Changing it doesn't sign you out on your other devices. Sign out on them yourself.
                    </p>
                    <PasswordForm sign_in={sign_in}/>
                </div>}
        </section>;
}

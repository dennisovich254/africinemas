"""`/invite/:token`: joining a cinema's staff from an invitation link (P3.7c).

Signed out, the page offers to sign in or create an account, and both come back here
(`?next=`). Signed in, "Accept invitation" joins the cinema with the invited role (the
server checks the link, P2.5) and opens its back-office. The email the person signed in
with goes along, so the cinema's staff list can say who they are.
"""

import from react { useState }
import from "@jac/runtime" { useNavigate, useParams, jacIsLoggedIn }
import from ..shell.AppLink { AppLink }
import from ...components.ui.button { Button }
import from ...components.ui.spinner { Spinner }
import from core.tenancy.staff_api { accept_invite }  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
import from .AuthLayout { AuthLayout, FormError }
import from .session { signed_in_email }

glob LINK_CLASSES: str = "inline-flex min-h-11 w-full items-center justify-center rounded-md border px-4 font-medium";

def:pub InvitePage -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    navigate: any = useNavigate();  # jac:ignore[W1037,W1051]
    token: str = params["token"] or "";
    [busy, set_busy] = useState(False);
    [error, set_error] = useState("");
    here = f"/invite/{token}";

    async def accept {
        answer: any = None;  # jac:ignore[W1037]
        set_busy(True);
        set_error("");
        try {
            answer = await accept_invite(token, signed_in_email());  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("accept_invite failed", e);
            set_busy(False);
            set_error(
                "We couldn't reach AfriCinemas. Check your connection and try again."
            );
            return;
        }
        set_busy(False);
        if answer["ok"] {
            navigate(f"/app/{answer['slug']}");
            return;
        }
        if answer["error"]["code"] == "invalid_invite" {
            set_error(
                "This invitation has expired or was already used. Ask the person who invited you for a new link."
            );
        } else {
            set_error(answer["error"]["message"]);
        }
    }

    if not jacIsLoggedIn() {
        return
            <AuthLayout
                title="You've been invited"
                description="Someone has invited you to join their cinema's staff on AfriCinemas. Sign in, or create an account, to accept."
            >
                <div className="flex flex-col gap-3" data-testid="invite-page">
                    <Button asChild={True} className="min-h-11 w-full">
                        <AppLink to={f"/login?next={here}"}>Sign in</AppLink>
                    </Button>
                    <AppLink to={f"/signup?next={here}"} className={LINK_CLASSES}>
                        Create an account
                    </AppLink>
                </div>
            </AuthLayout>;
    }
    return
        <AuthLayout
            title="Join the team"
            description="Accept to join the cinema's staff with the role you were invited for."
        >
            <div className="flex flex-col gap-3" data-testid="invite-page">
                <FormError message={error}/>
                <Button className="min-h-11 w-full" disabled={busy} onClick={accept}>
                    {busy and <Spinner aria-hidden="true"/>}{"Joining…"
                        if busy
                        else "Accept invitation"}
                </Button>
                <AppLink to="/app" className={LINK_CLASSES}>Not now</AppLink>
            </div>
        </AuthLayout>;
}

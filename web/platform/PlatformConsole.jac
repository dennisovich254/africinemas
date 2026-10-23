"""`/` and `/:section` on the platform's address: the AfriCinemas platform console (P13.1).

For AfriCinemas' own team, apart from every cinema's back office, signed in with a
platform account (P13.1b.a; /sign-in), on an address of its own (P13.1b.b). On opening, the page asks the server who
the caller is on the platform (platform_whoami) and shows the console only to platform
staff; anyone else (someone removed, say) is told plainly that this area is for
AfriCinemas staff. The server checks every request again, so the page is never the guard.

Sections so far: Overview (who you are, your role, what it lets you do, and the
platform's figures, P13.4; web/platform/OverviewFigures.jac), Cinemas (the
directory and each cinema's page, P13.2; web/platform/CinemasPages.jac) and, for super
admins, the Audit log (P13.3; web/platform/PlatformAuditPage.jac) and Platform staff: everyone with a role, inviting someone by email with a role (a
link to send them, valid 72 hours; "Invited" until they set their password, with a new
link on request), changing a role, and removing someone (asks first). Super admins set
in the server's settings show as such to the settings' own and can't be changed here;
only they are offered "Super admin", and only they can change or remove a super admin
made here.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams, useNavigate }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" { Logout01Icon }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.platform.staff_api {
    platform_whoami,  # jac:ignore[W2037] authenticated endpoint
    platform_staff,  # jac:ignore[W2037]
    invite_platform_member,  # jac:ignore[W2037]
    set_platform_role,  # jac:ignore[W2037]
    remove_platform_staff  # jac:ignore[W2037]
}
import from ..shell.AppShell { AppShell }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..backoffice.PlainLayout { PlainLayout }
import from .platform_session { platform_sign_out }
import from .CinemasPages { CinemasList, CinemaDetail }
import from .PlatformAuditPage { PlatformAuditPage }
import from .OverviewFigures { OverviewFigures }
import from .SupportPages { SupportInbox, SupportRequestPage }
import from ..support.live { use_open_requests }
import from ..backoffice.form_parts { ConfirmDelete, on_input, submit_with }

glob ROLE_CHOICES: list[tuple[str, str]] = [
         ("reviewer", "Reviewer"),
         ("support", "Support"),
         ("super_admin", "Super admin")
     ],
     ROLE_HELP: dict[str, str] = {
         "super_admin": "Everything, including adding and removing platform staff.",
         "reviewer": "Reviews cinemas for verification, and suspends or reinstates them.",
         "support": "Answers cinemas' technical support requests."
     },
     SELECT_CLASSES: str = "min-h-11 rounded-md border border-input bg-background px-3 text-sm";

def:pub may(me: dict[str, any], permission: str) -> bool {  # jac:ignore[W1037]
    found: list[str] = me["permissions"] or [];
    return permission in found;
}

def PlatformAccount -> JsxElement {
    # Signs out of the platform only: cinema sign-ins in this browser stay.
    nav = useNavigate();
    def leave {
        platform_sign_out();
        nav("/sign-in", {"replace": True});
    }
    return
        <Button
            variant="ghost"
            className="min-h-11 justify-start"
            onClick={leave}
            data-testid="platform-sign-out"
        >
            <HugeiconsIcon icon={Logout01Icon} strokeWidth={2} aria-hidden="true"/>
            Sign out
        </Button>;
}

def join_address(token: str) -> str {
    win: any = window;  # jac:ignore[W1037,W2001]
    return f"{win.location.origin}/join#{token}";
}

def InviteLink(email: str, link: str, hours: int) -> JsxElement {
    # The invitation to send: there's no email from here yet, so it's copied.
    [copied, set_copied] = useState(False);
    async def copy {
        win: any = window;  # jac:ignore[W1037,W2001]
        try {
            await win.navigator.clipboard.writeText(link);
            set_copied(True);
        } except Exception as e {
            console.warn("couldn't copy the link", e);
        }
    }
    return
        <section
            data-testid="platform-invite-link"
            className="flex flex-col gap-2 rounded-lg border bg-card p-4"
        >
            <h2 className="text-lg font-semibold">{f"Send {email} this link"}</h2>
            <p className="text-sm text-muted-foreground">
                {f"It lets them choose their password and works once, for {hours} hours. Send it only to them, by a channel you trust."}
            </p>
            <Input
                readOnly={True}
                value={link}
                aria-label="Invitation link"
                className="min-h-11 font-mono text-xs"
                data-testid="platform-invite-address"
            />
            <Button variant="outline" className="min-h-11 w-fit px-4" onClick={copy}>
                {"Copied" if copied else "Copy link"}
            </Button>
        </section>;
}

def StaffPage(me: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    # Only super admins from the server's settings make, change or remove super admins.
    settings_admin: bool = me["settings_admin"] or False;
    choices: list[tuple[str, str]] = [
        c
        for c in ROLE_CHOICES
        if settings_admin or c[0] != "super_admin"
    ];
    [rows, set_rows] = useState(None);
    [email, set_email] = useState("");
    [role, set_role] = useState("reviewer");
    [message, set_message] = useState("");
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);
    [asking, set_asking] = useState("");
    # The last invitation made: {email, link, hours}.
    [invited, set_invited] = useState(None);

    async def run(work: any, done: str) -> any {  # jac:ignore[W1037]
        set_busy(True);
        set_problem("");
        set_message("");
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await work();
        } except Exception as e {
            console.warn("platform staff request failed", e);
        }
        set_busy(False);
        if answer is None {
            set_problem(
                "We couldn't reach the server. Check your connection and try again."
            );
            return False;
        }
        if not answer["ok"] {
            set_problem(answer["error"]["message"]);
            return False;
        }
        set_rows(answer["staff"]);
        set_message(done);
        return answer;
    }

    async def load {
        await run(lambda -> any { return platform_staff(); }, "");  # jac:ignore[W1037,W2037]
    }

    def start {
        load();
    }
    useEffect(start, []);

    async def invite(wanted: str, picked: str) {
        set_invited(None);
        answer: any = await run(  # jac:ignore[W1037]
            lambda -> any { return invite_platform_member(wanted, picked); },  # jac:ignore[W1037,W2037]
            f"Invited {wanted}."
        );
        if answer {
            set_email("");
            set_invited(
                {
                    "email": wanted,
                    "link": join_address(answer["token"]),
                    "hours": answer["expires_in_hours"]
                }
            );
        }
    }

    async def add {
        wanted: str = email.strip();
        if not wanted {
            set_problem("Enter their email.");
            return;
        }
        await invite(wanted, role);
    }

    async def change(who: str, picked: str) {
        await run(
            lambda -> any { return set_platform_role(who, picked); },  # jac:ignore[W1037,W2037]
            f"Changed {who}'s role."
        );
    }

    async def remove(who: str) {
        set_asking("");
        await run(
            lambda -> any { return remove_platform_staff(who); },  # jac:ignore[W1037,W2037]
            f"Removed {who}. They lost access at once."
        );
    }

    if rows is None and not problem {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading platform staff…
            </p>;
    }
    listed: list[dict[str, any]] = rows or [];  # jac:ignore[W1037]
    made: dict[str, any] | None = invited;  # jac:ignore[W1037]
    return
        <div className="flex max-w-3xl flex-col gap-6" data-testid="platform-staff">
            <p className="text-sm text-muted-foreground">
                AfriCinemas' own team. They're separate from every cinema's staff and customers, and each role reaches only its own part of the console.
            </p>
            <p
                role="status"
                aria-live="polite"
                className="text-sm empty:hidden"
                data-testid="platform-message"
            >
                {message}
            </p>
            {problem
                and <Alert variant="destructive" role="alert">
                    <AlertDescription>{problem}</AlertDescription>
                </Alert>}
            {made
                and <InviteLink
                    email={made["email"]}
                    link={made["link"]}
                    hours={made["hours"]}
                />}
            <ul className="flex flex-col divide-y rounded-lg border bg-card">
                {[
                    <li
                        key={r["email"]}
                        data-testid="platform-member"
                        className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between"
                    >
                        <div className="flex min-w-0 flex-col gap-0.5">
                            <span className="break-all font-medium">
                                {r["email"]}{not r["joined"]
                                    and <Badge
                                        variant="outline"
                                        className="ml-2"
                                        data-testid="member-invited"
                                    >
                                        Invited
                                    </Badge>}
                            </span>
                            <span className="text-sm text-muted-foreground">
                                {ROLE_HELP[r["role"]]}
                            </span>
                        </div>
                        {r["fixed"]
                            and <div
                                className="flex flex-col items-start gap-1 sm:items-end"
                            >
                                <Badge>{r["role_label"]}</Badge>
                                <span className="text-xs text-muted-foreground">
                                    Set in the server's settings
                                </span>
                            </div>}
                        {not r["fixed"]
                            and not settings_admin
                            and r["role"] == "super_admin"
                            and <Badge>{r["role_label"]}</Badge>}
                        {not r["fixed"]
                            and (settings_admin or r["role"] != "super_admin")
                            and <div className="flex flex-wrap items-center gap-2">
                                <label
                                    className="sr-only"
                                    htmlFor={f"role-{r['email']}"}
                                >
                                    {f"Role for {r['email']}"}
                                </label>
                                <select
                                    id={f"role-{r['email']}"}
                                    data-testid="member-role"
                                    value={r["role"]}
                                    disabled={busy}
                                    onChange={on_input(
                                        lambda (picked: str) { change(
                                            r["email"], picked
                                        ); }
                                    )}
                                    className={SELECT_CLASSES}
                                >
                                    {[
                                        <option key={k} value={k}>{n}</option>
                                        for (k, n) in choices
                                    ]}
                                </select>
                                {not r["joined"]
                                    and <Button
                                        variant="outline"
                                        className="min-h-11 px-3"
                                        disabled={busy}
                                        aria-label={f"New invitation link for {r[
                                            'email'
                                        ]}"}
                                        onClick={lambda { invite(
                                            r["email"], r["role"]
                                        ); }}
                                    >
                                        New link
                                    </Button>}
                                {asking != r["email"]
                                    and <Button
                                        variant="ghost"
                                        className="min-h-11 px-3"
                                        disabled={busy}
                                        aria-label={f"Remove {r['email']}"}
                                        onClick={lambda { set_asking(r["email"]); }}
                                    >
                                        Remove
                                    </Button>}
                            </div>}
                        {asking == r["email"]
                            and <ConfirmDelete
                                question={f"Remove {r['email']}?"}
                                detail="They lose access to the platform console at once, and an unused invitation stops working."
                                confirm_label="Remove"
                                on_confirm={lambda { remove(r["email"]); }}
                                on_cancel={lambda { set_asking(""); }}
                                busy={busy}
                            />}
                    </li> for r in listed
                ]}
            </ul>
            <form
                data-testid="add-platform-member"
                className="flex flex-col gap-3 rounded-lg border bg-card p-4"
                onSubmit={submit_with(lambda { add(); })}
            >
                <h2 className="text-lg font-semibold">Invite someone</h2>
                <div className="grid gap-3 sm:grid-cols-[1fr_12rem]">
                    <div className="flex min-w-0 flex-col gap-1.5">
                        <Label htmlFor="platform-email">Their email</Label>
                        <Input
                            id="platform-email"
                            type="email"
                            autoComplete="off"
                            value={email}
                            onChange={on_input(set_email)}
                            className="min-h-11"
                        />
                    </div>
                    <div className="flex flex-col gap-1.5">
                        <Label htmlFor="platform-role">Role</Label>
                        <select
                            id="platform-role"
                            value={role}
                            onChange={on_input(set_role)}
                            className={SELECT_CLASSES}
                        >
                            {[
                                <option key={k} value={k}>{n}</option>
                                for (k, n) in choices
                            ]}
                        </select>
                    </div>
                </div>
                <p className="text-sm text-muted-foreground">{ROLE_HELP[role]}</p>
                <p className="text-sm text-muted-foreground">
                    You get a link to send them. They choose a password for a platform account of their own, separate from any cinema account.
                </p>
                <Button
                    type="submit"
                    className="min-h-11 w-fit px-5"
                    disabled={busy or not email.strip()}
                >
                    Invite
                </Button>
            </form>
        </div>;
}

def Overview(me: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    return
        <div className="flex max-w-5xl flex-col gap-4" data-testid="platform-overview">
            <section className="flex flex-col gap-2 rounded-lg border bg-card p-4">
                <h2 className="text-lg font-semibold">Welcome</h2>
                <p>
                    {f"You're signed in as {me['email']}."}
                    <Badge className="ml-2" data-testid="platform-role">
                        {me["role_label"]}
                    </Badge>
                </p>
                <p className="text-sm text-muted-foreground">{ROLE_HELP[me["role"]]}</p>
            </section>
            {may(me, "platform.read") and <OverviewFigures/>}
        </div>;
}

def:pub PlatformConsole -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    section: str = params["section"] or "";
    item: str = params["item"] or "";
    [me, set_me] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_whoami();  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("platform_whoami failed", e);
            set_failed(True);
            return;
        }
        set_me(answer);
    }

    def start {
        load();
    }
    useEffect(start, []);
    # Support's count: requests waiting on us (P13.5a), for support staff.
    seen: dict[str, any] = me or {};  # jac:ignore[W1037]
    granted: list[str] = seen["permissions"] or [];
    may_support: bool = bool(seen["platform"]) and "platform.support" in granted;
    waiting = use_open_requests(may_support);

    if failed {
        return
            <PlainLayout title="AfriCinemas platform" account={<PlatformAccount/>}>
                <Alert variant="destructive">
                    <AlertDescription>
                        We couldn't reach the server. Refresh the page to try again.
                    </AlertDescription>
                </Alert>
            </PlainLayout>;
    }
    if me is None {
        return
            <ThemeProvider surface="backoffice">
                <main className="flex min-h-svh items-center justify-center">
                    <p
                        role="status"
                        className="flex items-center gap-2 text-muted-foreground"
                    >
                        <Spinner aria-hidden="true"/>
                        Loading…
                    </p>
                </main>
            </ThemeProvider>;
    }
    shown: dict[str, any] = me;  # jac:ignore[W1037]
    if not shown["platform"] {
        return
            <PlainLayout title="AfriCinemas platform" account={<PlatformAccount/>}>
                <section
                    data-testid="not-platform"
                    className="flex max-w-xl flex-col items-start gap-3 rounded-lg border bg-card p-6"
                >
                    <h2 className="text-xl font-semibold">
                        This area is for AfriCinemas staff
                    </h2>
                    <p className="text-muted-foreground">
                        Your account isn't on the AfriCinemas team.
                    </p>
                </section>
            </PlainLayout>;
    }
    nav: list[dict[str, str]] = [{"label": "Overview", "to": "/", "key": ""}];
    if may(shown, "platform.read") {
        nav.append({"label": "Cinemas", "to": "/cinemas", "key": "cinemas"});
    }
    if may(shown, "platform.support") {
        nav.append(
            {
                "label": "Support",
                "to": "/support",
                "key": "support",
                "count": str(waiting) if waiting else ""
            }
        );
    }
    if may(shown, "platform.staff") {
        nav.append({"label": "Platform staff", "to": "/staff", "key": "staff"});
    }
    if may(shown, "platform.audit") {
        nav.append({"label": "Audit log", "to": "/audit", "key": "audit"});
    }
    # Only Cinemas and Support have pages under them (/cinemas/<slug>, /support/<id>).
    allowed = section in [n["key"] for n in nav]
        and (not item or section in ["cinemas", "support"]);
    title = [
        n["label"]
        for n in nav
        if n["key"] == section
    ][0]
        if allowed
        else "Not here";
    return
        <ThemeProvider surface="backoffice">
            <AppShell
                title={title}
                nav={nav}
                brand="AfriCinemas platform"
                home="/"
                account={<PlatformAccount/>}
            >
                {section == "" and <Overview me={shown}/>}{section == "cinemas"
                    and allowed
                    and not item
                    and <CinemasList/>}{section == "cinemas"
                    and allowed
                    and item
                    and <CinemaDetail
                        slug={item}
                        audit={may(shown, "platform.audit")}
                    />}{section == "audit" and allowed and <PlatformAuditPage/>}{section
                    == "support"
                    and allowed
                    and not item
                    and <SupportInbox/>}{section == "support"
                    and allowed
                    and item
                    and <SupportRequestPage request_id={item}/>}{section == "staff"
                    and allowed
                    and <StaffPage me={shown}/>}{not allowed
                    and <p
                        data-testid="platform-no-access"
                        className="text-muted-foreground"
                    >
                        Your platform role doesn't include this page.
                    </p>}
            </AppShell>
        </ThemeProvider>;
}

"""`/platform` and `/platform/:section`: the AfriCinemas platform console (P13.1).

For AfriCinemas' own team, apart from every cinema's back office. On opening, the page
asks the server who the caller is on the platform (platform_whoami, with the email this
browser signed in with), and shows the console only to platform staff; anyone else is
told plainly that this area is for AfriCinemas staff. The server checks every request
again, so the page is never the guard.

Sections so far: Overview (who you are, your role, what it lets you do) and, for super
admins, Platform staff: everyone with a role, adding someone by their sign-in email with
a role, changing a role, and removing someone (asks first). Super admins set in the
server's settings show as such and can't be changed here.
"""

import from react { useState, useEffect }
import from "@jac/runtime" { useParams }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.platform.staff_api {
    platform_whoami,  # jac:ignore[W2037] authenticated endpoint
    platform_staff,  # jac:ignore[W2037]
    set_platform_role,  # jac:ignore[W2037]
    remove_platform_staff  # jac:ignore[W2037]
}
import from ..shell.AppShell { AppShell }
import from ..shell.AppLink { AppLink }
import from ..theme.ThemeProvider { ThemeProvider }
import from ..auth.session { signed_in_email }
import from ..backoffice.PlainLayout { PlainLayout, AccountActions }
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

def StaffPage -> JsxElement {
    [rows, set_rows] = useState(None);
    [email, set_email] = useState("");
    [role, set_role] = useState("reviewer");
    [message, set_message] = useState("");
    [problem, set_problem] = useState("");
    [busy, set_busy] = useState(False);
    [asking, set_asking] = useState("");

    async def run(work: any, done: str) -> bool {  # jac:ignore[W1037]
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
        return True;
    }

    async def load {
        await run(lambda -> any { return platform_staff(); }, "");  # jac:ignore[W1037,W2037]
    }

    def start {
        load();
    }
    useEffect(start, []);

    async def add {
        wanted: str = email.strip();
        picked: str = role;
        if not wanted {
            set_problem("Enter their sign-in email.");
            return;
        }
        if await run(
            lambda -> any { return set_platform_role(wanted, picked); },  # jac:ignore[W1037,W2037]
            f"{wanted} is now {[
                n
                for (k, n) in ROLE_CHOICES
                if k == picked
            ][0]}."
        ) {
            set_email("");
        }
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
            <ul className="flex flex-col divide-y rounded-lg border bg-card">
                {[
                    <li
                        key={r["email"]}
                        data-testid="platform-member"
                        className="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between"
                    >
                        <div className="flex min-w-0 flex-col gap-0.5">
                            <span className="break-all font-medium">{r["email"]}</span>
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
                                        for (k, n) in ROLE_CHOICES
                                    ]}
                                </select>
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
                                detail="They lose access to the platform console at once."
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
                <h2 className="text-lg font-semibold">Add someone</h2>
                <div className="grid gap-3 sm:grid-cols-[1fr_12rem]">
                    <div className="flex min-w-0 flex-col gap-1.5">
                        <Label htmlFor="platform-email">Their sign-in email</Label>
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
                                for (k, n) in ROLE_CHOICES
                            ]}
                        </select>
                    </div>
                </div>
                <p className="text-sm text-muted-foreground">{ROLE_HELP[role]}</p>
                <p className="text-sm text-muted-foreground">
                    They sign in with their own AfriCinemas account using this email, then open the platform console.
                </p>
                <Button
                    type="submit"
                    className="min-h-11 w-fit px-5"
                    disabled={busy or not email.strip()}
                >
                    Add
                </Button>
            </form>
        </div>;
}

def Overview(me: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
    return
        <div className="flex max-w-3xl flex-col gap-4" data-testid="platform-overview">
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
            <p className="text-sm text-muted-foreground">
                The cinemas directory, the platform audit log, the overview figures and the support inbox are added here next (plan Phase 13).
            </p>
        </div>;
}

def:pub PlatformConsole -> JsxElement {
    params: any = useParams();  # jac:ignore[W1037,W1051]
    section: str = params["section"] or "";
    [me, set_me] = useState(None);
    [failed, set_failed] = useState(False);

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        try {
            answer = await platform_whoami(signed_in_email());  # jac:ignore[W2037]
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

    if failed {
        return
            <PlainLayout
                title="AfriCinemas platform"
                account={<AccountActions slugs={[]}/>}
            >
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
            <PlainLayout
                title="AfriCinemas platform"
                account={<AccountActions slugs={[]}/>}
            >
                <section
                    data-testid="not-platform"
                    className="flex max-w-xl flex-col items-start gap-3 rounded-lg border bg-card p-6"
                >
                    <h2 className="text-xl font-semibold">
                        This area is for AfriCinemas staff
                    </h2>
                    <p className="text-muted-foreground">
                        Your account isn't on the AfriCinemas team. Your cinemas are in your back office.
                    </p>
                    <AppLink
                        to="/app"
                        className="inline-flex min-h-11 items-center rounded-md border px-4 font-medium hover:bg-muted"
                    >
                        Go to your cinemas
                    </AppLink>
                </section>
            </PlainLayout>;
    }
    nav: list[dict[str, str]] = [{"label": "Overview", "to": "/platform", "key": ""}];
    if may(shown, "platform.staff") {
        nav.append(
            {"label": "Platform staff", "to": "/platform/staff", "key": "staff"}
        );
    }
    allowed = section in [n["key"] for n in nav];
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
                home="/platform"
                account={<AccountActions slugs={[]} switch_to="/app"/>}
            >
                {section == "" and <Overview me={shown}/>}{section == "staff"
                    and allowed
                    and <StaffPage/>}{not allowed
                    and <p
                        data-testid="platform-no-access"
                        className="text-muted-foreground"
                    >
                        Your platform role doesn't include this page.
                    </p>}
            </AppShell>
        </ThemeProvider>;
}

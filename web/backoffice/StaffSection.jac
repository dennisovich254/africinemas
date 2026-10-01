"""`/app/:slug/staff`: the cinema's staff and invitations (P3.7c), on the P2.5 endpoints.

Each member shows who they are (their verified email and the inviter's note), their
roles (named venues for roles limited to one) and whether they're active. Staff with the
matching permission invite someone (a role, an optional venue, a note; "Invite someone"
opens the form) and share the one-time link; change a member's role; disable or
re-enable them; remove them (asked first). Nobody can change their own membership, and
the server refuses giving a role with permissions the actor doesn't hold.
"""

import from react { useState, useEffect }
import from ...components.ui.alert { Alert, AlertDescription }
import from ...components.ui.badge { Badge }
import from ...components.ui.button { Button }
import from ...components.ui.input { Input }
import from ...components.ui.label { Label }
import from ...components.ui.spinner { Spinner }
import from core.tenancy.staff_api {
    list_staff,  # jac:ignore[W2037] def:priv endpoint over the server pin (JI-027)
    invite_staff,  # jac:ignore[W2037]
    change_staff_roles,  # jac:ignore[W2037]
    set_staff_status,  # jac:ignore[W2037]
    remove_staff  # jac:ignore[W2037]
}
import from core.catalog.venue_api { list_venues }  # jac:ignore[W2037]
import from .form_parts { FieldError, ConfirmDelete, error_id, on_input, submit_with }
import from .nav { role_label }

glob SELECT_CLASSES: str = "min-h-11 w-full rounded-md border border-input bg-background px-3 text-sm",
     # The roles in core/authz/policy.jac, in the order people usually need them.
     ROLES: list[str] = [
         "box_office_agent",
         "usher",
         "box_office_manager",
         "general_manager",
         "content_manager",
         "finance_manager",
         "auditor",
         "it_admin",
         "tenant_admin",
         "owner"
     ],
     # Roles that can be limited to one venue (policy.VENUE_SCOPABLE_ROLES).
     VENUE_ROLES: list[str] = [
         "general_manager",
         "box_office_manager",
         "box_office_agent",
         "usher"
     ];

def:pub role_name(key: str, venue_names: dict[str, str]) -> str {
    # "box_office_agent@<id>" -> "Box office agent (Westgate)".
    parts = key.split("@");
    name = role_label(parts[0]);
    if len(parts) > 1 {
        place = venue_names[parts[1]] or "a venue";
        return name + " (" + place + ")";
    }
    return name;
}

def:pub who(member: dict[str, any]) -> str {  # jac:ignore[W1037]
    # The member's verified email, else the inviter's note, else a plain description.
    return member["email"] or member["label"] or "Staff member";
}

def:pub StaffSection(slug: str, permissions: list[str]) -> JsxElement {
    [staff, set_staff] = useState(None);
    [venues, set_venues] = useState([]);
    [failed, set_failed] = useState("");
    [busy, set_busy] = useState(False);
    [errors, set_errors] = useState({});
    [message, set_message] = useState("");
    [inviting, set_inviting] = useState(False);
    [invite, set_invite] = useState({"role": "", "venue": "", "note": ""});
    [made, set_made] = useState(None);
    [copied, set_copied] = useState(False);
    [editing, set_editing] = useState("");
    [new_role, set_new_role] = useState({"role": "", "venue": ""});
    [confirming, set_confirming] = useState(None);
    can_invite = "employees.invite" in permissions;
    can_assign = "employees.assign_roles" in permissions;
    can_disable = "employees.disable" in permissions;

    async def load {
        answer: any = None;  # jac:ignore[W1037]
        places: any = None;  # jac:ignore[W1037]
        try {
            answer = await list_staff(slug);  # jac:ignore[W2037]
            places = await list_venues(slug);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("list_staff failed", e);
            set_failed("We couldn't load your staff. Refresh the page to try again.");
            return;
        }
        if not answer["ok"] {
            set_failed(answer["error"]["message"]);
            return;
        }
        set_staff(answer["staff"]);
        set_venues(places["venues"] if places["ok"] else []);
    }

    # A named function, not a one-statement lambda (JI-028).
    def start_loading {
        load();
    }
    useEffect(start_loading, [slug]);

    field_errors: dict[str, str] = errors;
    asked: dict[str, str] = invite;
    changing: dict[str, str] = new_role;
    places: list[dict[str, any]] = venues;  # jac:ignore[W1037]
    venue_names: dict[str, str] = {};
    for v in places {
        venue_names[v["venue_id"]] = v["name"];
    }

    def only_error(field_id: str, text: str) {
        shown: dict[str, str] = {};
        if field_id {
            shown[field_id] = text;
        }
        set_errors(shown);
    }

    def copy_of(form: dict[str, str], key: str, value: str) -> dict[str, str] {
        changed: dict[str, str] = {};
        for k in form {
            changed[k] = form[k];
        }
        changed[key] = value;
        return changed;
    }

    async def create_invite {
        answer: any = None;  # jac:ignore[W1037]
        if not asked["role"] {
            only_error("invite-role", "Choose a role.");
            return;
        }
        venue = asked["venue"] if asked["role"] in VENUE_ROLES else "";
        set_busy(True);
        try {
            answer = await invite_staff(slug, asked["role"], venue, asked["note"]);  # jac:ignore[W2037]
        } except Exception as e {
            console.warn("invite_staff failed", e);
            set_busy(False);
            only_error("invite-role", "We couldn't create the invitation. Try again.");
            return;
        }
        set_busy(False);
        if not answer["ok"] {
            code = answer["error"]["code"];
            text = answer["error"]["message"];
            if code == "forbidden" {
                text = "You can only invite people to roles with permissions you have yourself.";
            }
            only_error(
                "invite-note" if code == "invalid_label" else "invite-role", text
            );
            return;
        }
        only_error("", "");
        win: any = window;  # jac:ignore[W1037,W2001]
        set_made(
            {
                "link": f"{win.location.origin}/invite/{answer['token']}",
                "expires": answer["expires_at"]
            }
        );
        set_copied(False);
        set_inviting(False);
        set_invite({"role": "", "venue": "", "note": ""});
    }

    async def copy_link {
        shown: dict[str, str] = made;
        try {
            clip: any = navigator.clipboard;  # jac:ignore[W1037,W2001]
            await clip.writeText(shown["link"]);
            set_copied(True);
        } except Exception as e {
            console.warn("copy failed", e);
            set_message("Copy didn't work here: select the link and copy it yourself.");
        }
    }

    async def step(call: any, member_id: str, done: str) -> bool {  # jac:ignore[W1037]
        # Runs one change to a member; refusals show under that member.
        answer: any = None;  # jac:ignore[W1037]
        set_busy(True);
        set_message("");
        try {
            answer = await call();
        } except Exception as e {
            console.warn("staff change failed", e);
            set_busy(False);
            only_error(f"problem-{member_id}", "We couldn't save that. Try again.");
            return False;
        }
        set_busy(False);
        if not answer["ok"] {
            text = answer["error"]["message"];
            if answer["error"]["code"] == "forbidden" {
                text = "You can't change this person: they hold permissions you don't.";
            }
            only_error(f"problem-{member_id}", text);
            return False;
        }
        only_error("", "");
        set_message(done);
        await load();
        return True;
    }

    def start_change(m: dict[str, any]) {  # jac:ignore[W1037]
        first: str = m["roles"][0] if len(m["roles"]) > 0 else "";
        parts = first.split("@");
        set_editing(m["member_id"]);
        set_new_role({"role": parts[0], "venue": parts[1] if len(parts) > 1 else ""});
        set_confirming(None);
        only_error("", "");
    }

    async def save_role(m: dict[str, any]) {  # jac:ignore[W1037]
        role = changing["role"];
        venue = changing["venue"] if role in VENUE_ROLES else "";
        key = f"{role}@{venue}" if venue else role;
        ok = await step(
            lambda -> any { return change_staff_roles(slug, m["member_id"], [key]); },  # jac:ignore[W1037,W2037]
            m["member_id"],
            f"{who(m)} is now {role_name(key, venue_names)}."
        );
        if ok {
            set_editing("");
        }
    }

    async def set_status(m: dict[str, any], status: str) {  # jac:ignore[W1037]
        await step(
            lambda -> any { return set_staff_status(slug, m["member_id"], status); },  # jac:ignore[W1037,W2037]
            m["member_id"],
            who(m)
                + (
                    " is disabled: they can sign in but can't work here."
                        if status == "disabled"
                        else " is active again."
                )
        );
    }

    async def confirm_remove {
        target: dict[str, str] = confirming;
        set_confirming(None);
        await step(
            lambda -> any { return remove_staff(slug, target["id"]); },  # jac:ignore[W1037,W2037]
            target["id"],
            f"{target['name']} is no longer staff here."
        );
    }

    if failed {
        return
            <Alert variant="destructive">
                <AlertDescription>{failed}</AlertDescription>
            </Alert>;
    }
    if staff is None {
        return
            <p role="status" className="flex items-center gap-2 text-muted-foreground">
                <Spinner aria-hidden="true"/>
                Loading your staff…
            </p>;
    }
    members: list[dict[str, any]] = staff;  # jac:ignore[W1037]
    asking: dict[str, str] | None = confirming;
    role_error = field_errors["invite-role"] or "";
    note_error = field_errors["invite-note"] or "";

    def RoleSelect(field_id: str, value: str, on_text: any) -> JsxElement {  # jac:ignore[W1037]
        problem = field_errors[field_id] or "";
        return
            <select
                id={field_id}
                value={value}
                aria-invalid={"true" if problem else "false"}
                aria-describedby={error_id(field_id) if problem else None}
                onChange={on_input(on_text)}
                className={SELECT_CLASSES}
            >
                <option value="">Choose a role</option>
                {[<option key={r} value={r}>{role_label(r)}</option> for r in ROLES]}
            </select>;
    }

    def VenueSelect(field_id: str, value: str, on_text: any) -> JsxElement {  # jac:ignore[W1037]
        return
            <select
                id={field_id}
                value={value}
                onChange={on_input(on_text)}
                className={SELECT_CLASSES}
            >
                <option value="">All venues</option>
                {[
                    <option key={v["venue_id"]} value={v["venue_id"]}>
                        {v["name"]}
                    </option> for v in places
                ]}
            </select>;
    }

    invite_form = <form
        data-testid="invite-form"
        className="grid gap-3 rounded-lg border p-4 sm:grid-cols-2"
        noValidate={True}
        onSubmit={submit_with(lambda { create_invite(); })}
    >
        <h2 className="text-lg font-semibold sm:col-span-2">Invite someone</h2>
        <div className="flex flex-col gap-1.5">
            <Label htmlFor="invite-role">Role</Label>
            {RoleSelect(
                "invite-role",
                asked["role"],
                lambda (text: str) { set_invite(copy_of(asked, "role", text)); }
            )}
            {role_error and <FieldError field_id="invite-role" error={role_error}/>}
        </div>
        {asked["role"] in VENUE_ROLES
            and <div className="flex flex-col gap-1.5">
                <Label htmlFor="invite-venue">Venue</Label>
                {VenueSelect(
                    "invite-venue",
                    asked["venue"],
                    lambda (text: str) { set_invite(copy_of(asked, "venue", text)); }
                )}
            </div>}
        <div className="flex flex-col gap-1.5 sm:col-span-2">
            <Label htmlFor="invite-note">Who is it for? (optional)</Label>
            <Input
                id="invite-note"
                value={asked["note"]}
                maxLength={60}
                placeholder="e.g. Wanjiru, weekend box office"
                aria-invalid={"true" if note_error else "false"}
                aria-describedby={error_id("invite-note")
                    if note_error
                    else "invite-note-hint"}
                onChange={on_input(
                    lambda (text: str) { set_invite(copy_of(asked, "note", text)); }
                )}
                className="min-h-11"
            />
            <p id="invite-note-hint" className="text-sm text-muted-foreground">
                Only your team sees this, to know who the invitation was for.
            </p>
            {note_error and <FieldError field_id="invite-note" error={note_error}/>}
        </div>
        <div className="flex flex-wrap gap-3 sm:col-span-2">
            <Button type="submit" className="min-h-11 px-5" disabled={busy}>
                Create invitation
            </Button>
            <Button
                type="button"
                variant="ghost"
                className="min-h-11 px-5"
                onClick={lambda {
                    set_inviting(False);
                    only_error("", "");
                }}
            >
                Cancel
            </Button>
        </div>
    </form>;

    shared: dict[str, str] | None = made;
    until = "";
    if shared is not None {
        moment: any = new(Date, shared["expires"]);  # jac:ignore[W1037,W2001]
        until = moment.toLocaleString();
    }
    link_box = shared is not None
        and <section
            aria-labelledby="link-heading"
            className="flex flex-col gap-3 rounded-lg border bg-card p-4"
        >
            <h2 id="link-heading" className="text-lg font-semibold">
                Share this invitation link
            </h2>
            <p className="text-sm text-muted-foreground">
                Send it to the person you're inviting, by message or email. It works once, until {until}. For your security it's only shown now; you can always create another.
            </p>
            <div className="flex flex-wrap gap-2">
                <Label htmlFor="invite-link" className="sr-only">Invitation link</Label>
                <Input
                    id="invite-link"
                    value={shared["link"]}
                    readOnly={True}
                    className="min-h-11 min-w-0 flex-1 basis-64 font-mono text-sm"
                />
                <Button type="button" className="min-h-11 px-5" onClick={copy_link}>
                    {"Copied" if copied else "Copy link"}
                </Button>
                <Button
                    type="button"
                    variant="ghost"
                    className="min-h-11 px-5"
                    onClick={lambda { set_made(None); }}
                >
                    Done
                </Button>
            </div>
        </section>;

    def MemberRow(m: dict[str, any]) -> JsxElement {  # jac:ignore[W1037]
        mid: str = m["member_id"];
        active = m["status"] == "active";
        problem = field_errors[f"problem-{mid}"] or "";
        manageable = not m["is_you"] and (can_assign or can_disable);
        return
            <li
                key={mid}
                data-testid="member"
                className={"flex flex-col gap-3 rounded-lg border bg-card p-4"
                    + ("" if active else " opacity-80")}
            >
                <div className="flex flex-wrap items-start justify-between gap-3">
                    <div className="flex min-w-0 flex-col gap-1">
                        <span className="flex flex-wrap items-center gap-2 font-medium">
                            <span className="break-all">{who(m)}</span>
                            {m["is_you"] and <Badge variant="secondary">You</Badge>}
                        </span>
                        {m["email"]
                            and m["label"]
                            and <span className="text-sm text-muted-foreground">
                                {m["label"]}
                            </span>}
                        <span className="text-sm">
                            {", ".join([role_name(r, venue_names) for r in m["roles"]])}
                        </span>
                    </div>
                    <Badge
                        variant={"secondary" if active else "outline"}
                        data-testid="member-status"
                    >
                        {"Active" if active else "Disabled"}
                    </Badge>
                </div>
                {manageable
                    and editing != mid
                    and <div className="flex flex-wrap gap-2">
                        {can_assign
                            and <Button
                                variant="outline"
                                className="min-h-11 px-4"
                                disabled={busy}
                                onClick={lambda { start_change(m); }}
                            >
                                Change role
                            </Button>}{can_disable
                            and <Button
                                variant="outline"
                                className="min-h-11 px-4"
                                disabled={busy}
                                onClick={lambda { set_status(
                                    m, "disabled" if active else "active"
                                ); }}
                            >
                                {"Disable" if active else "Enable"}
                            </Button>}{can_disable
                            and <Button
                                variant="ghost"
                                className="min-h-11 px-4"
                                disabled={busy}
                                onClick={lambda {
                                    set_confirming({"id": mid, "name": who(m)});
                                    set_editing("");
                                }}
                            >
                                Remove
                            </Button>}
                    </div>}
                {editing == mid
                    and <form
                        className="grid gap-3 rounded-lg border p-3 sm:grid-cols-2"
                        noValidate={True}
                        onSubmit={submit_with(lambda { save_role(m); })}
                    >
                        <div className="flex flex-col gap-1.5">
                            <Label htmlFor={f"role-for-{mid}"}>New role</Label>
                            {RoleSelect(
                                f"role-for-{mid}",
                                changing["role"],
                                lambda (text: str) { set_new_role(
                                    copy_of(changing, "role", text)
                                ); }
                            )}
                        </div>
                        {changing["role"] in VENUE_ROLES
                            and <div className="flex flex-col gap-1.5">
                                <Label htmlFor={f"venue-for-{mid}"}>Venue</Label>
                                {VenueSelect(
                                    f"venue-for-{mid}",
                                    changing["venue"],
                                    lambda (text: str) { set_new_role(
                                        copy_of(changing, "venue", text)
                                    ); }
                                )}
                            </div>}
                        <div className="flex flex-wrap gap-3 sm:col-span-2">
                            <Button
                                type="submit"
                                className="min-h-11 px-5"
                                disabled={busy or not changing["role"]}
                            >
                                Save role
                            </Button>
                            <Button
                                type="button"
                                variant="ghost"
                                className="min-h-11 px-5"
                                onClick={lambda {
                                    set_editing("");
                                    only_error("", "");
                                }}
                            >
                                Keep the role
                            </Button>
                        </div>
                    </form>}
                {asking is not None
                    and asking["id"] == mid
                    and <ConfirmDelete
                        question={f"Remove {asking['name']} from your staff?"}
                        detail="They can't work at your cinema any more. To bring them back, send a new invitation."
                        confirm_label="Remove from staff"
                        cancel_label="Keep them"
                        on_confirm={confirm_remove}
                        on_cancel={lambda { set_confirming(None); }}
                        busy={busy}
                    />}
                {problem and <FieldError field_id={f"problem-{mid}"} error={problem}/>}
            </li>;
    }

    return
        <div className="flex flex-col gap-6" data-testid="staff-page">
            <div className="flex flex-wrap items-center justify-between gap-3">
                <p className="text-sm text-muted-foreground">
                    {"1 person"
                        if len(members) == 1
                        else f"{len(members)} people"} on your staff
                </p>
                {can_invite
                    and not inviting
                    and <Button
                        className="min-h-11 w-fit px-5"
                        onClick={lambda {
                            set_inviting(True);
                            set_made(None);
                            only_error("", "");
                        }}
                    >
                        Invite someone
                    </Button>}
            </div>
            <p role="status" aria-live="polite" className="text-sm empty:hidden">
                {message}
            </p>
            {inviting and invite_form}
            {link_box}
            <section aria-labelledby="staff-heading" className="flex flex-col gap-3">
                <h2 id="staff-heading" className="text-lg font-semibold">Your team</h2>
                <ul className="grid gap-3 lg:grid-cols-2">
                    {[MemberRow(m) for m in members]}
                </ul>
            </section>
        </div>;
}

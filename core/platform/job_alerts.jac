"""Telling the team when a background job goes silent (P16.2), or M-Pesa is likely down
across the platform (P16.3, mpesa_watch.jac).

check_jobs runs every CHECK_SECONDS: for each job now silent (jobs.jac), the team is
emailed once ("… has stopped"); when it runs again, once more ("… is running again").
Which were reported is kept (ALERTED, one claim per job) so each is said once. The team
is AFRICINEMAS_ALERT_EMAILS (comma separated), or the super admins when it's unset. No
alert carries a customer's details: only the job, and when it last ran.

Emails go through the mailer like every other (the development outbox until the
email provider is set up, 16.6).
"""

import os;
import json;
import html;
import from email.utils { formataddr }
import from core.clock { now }
import from core.claims { claim, holder, take_claim }
import from core.notify.mailer { OutgoingMail, send, from_address }
import from core.platform.staff_api { allowlisted }
import from core.platform.jobs { job_status, ran }
import from core.platform.mpesa_watch { mpesa_state, probe_mpesa }

glob ALERT_ENV: str = "AFRICINEMAS_ALERT_EMAILS",
     ALERTED: str = "job-alerted",
     CHECK_SECONDS: int = int(os.environ.get("AFRICINEMAS_JOB_CHECK_SECONDS", "300"));

def team -> list[str] {
    raw = os.environ.get(ALERT_ENV, "");
    found = [
        e.strip().lower()
        for e in raw.split(",")
        if e.strip()
    ];
    return found if found else allowlisted();
}

def alert_mail(to: str, label: str, stopped: bool, last_ran: str) -> OutgoingMail {
    if stopped {
        subject = f"AfriCinemas: {label} has stopped";
        lead = f"The background job {label} hasn't run since {last_ran
            or 'it started'}. Check the server's log, and the console's overview.";
    } else {
        subject = f"AfriCinemas: {label} is running again";
        lead = f"The background job {label} is running again.";
    }
    return OutgoingMail(
        to=to,
        sender=formataddr(("AfriCinemas alerts", from_address())),
        subject=subject,
        text=f"{lead}\n",
        html=f"<p>{html.escape(lead)}</p>"
    );
}

def check_jobs_now -> int {
    # Emails the team about each job that went silent or came back; how many emails.
    sent = 0;
    for row in job_status(now()) {
        told = holder(ALERTED, row["name"]);
        stopped = row["state"] == "silent";
        if stopped == bool(told) {
            continue;
        }
        for address in team() {
            if send(alert_mail(address, row["label"], stopped, row["last_ran"])) {
                sent += 1;
            }
        }
        if stopped {
            claim(ALERTED, row["name"], json.dumps({"at": now().isoformat()}));
        } else {
            take_claim(ALERTED, row["name"]);
        }
    }
    return sent;
}

def mpesa_mail(to: str, state: dict[str, any]) -> OutgoingMail {  # jac:ignore[W1037]
    if state["likely_down"] {
        subject = "AfriCinemas: M-Pesa is likely down";
        seen: list[str] = [];
        if "daraja" in state["why"] {
            seen.append("Daraja hasn't answered our last two checks");
        }
        if "payments" in state["why"] {
            seen.append(
                f"{state['failures']} of the last {state[
                    'attempts'
                ]} payments failed on Safaricom's side"
            );
        }
        lead = f"{' and '.join(
            seen
        )}. That's likely Safaricom, not the cinemas. Check Safaricom's channels, post on the status page, and tell the cinemas to take cash meanwhile.";
    } else {
        subject = "AfriCinemas: M-Pesa payments are going through again";
        lead = "M-Pesa is answering again, and payments are going through.";
    }
    links = " ".join([f"{l[0]}: {l[1]}" for l in state["links"]]);
    return OutgoingMail(
        to=to,
        sender=formataddr(("AfriCinemas alerts", from_address())),
        subject=subject,
        text=f"{lead}\n\n{links}\n",
        html=f"<p>{html.escape(lead)}</p><p>{html.escape(links)}</p>"
    );
}

def _flip(key: str, up: bool, mail: any) -> int {  # jac:ignore[W1037]
    # Emails the team when `key` comes up or goes down (mail(address)); how many.
    told = holder(ALERTED, key);
    if up == bool(told) {
        return 0;
    }
    sent = 0;
    for address in team() {
        if send(mail(address)) {
            sent += 1;
        }
    }
    if up {
        claim(ALERTED, key, json.dumps({"at": now().isoformat()}));
    } else {
        take_claim(ALERTED, key);
    }
    return sent;
}

def keys_mail(to: str, refused: bool) -> OutgoingMail {
    if refused {
        subject = "AfriCinemas: M-Pesa refused our own keys";
        lead = "Daraja answered, but refused AfriCinemas' own M-Pesa keys (DARAJA_*): invoices can't be paid with M-Pesa until they're fixed. This isn't an outage.";
    } else {
        subject = "AfriCinemas: M-Pesa accepts our keys again";
        lead = "Daraja accepts AfriCinemas' own M-Pesa keys again.";
    }
    return OutgoingMail(
        to=to,
        sender=formataddr(("AfriCinemas alerts", from_address())),
        subject=subject,
        text=f"{lead}\n",
        html=f"<p>{html.escape(lead)}</p>"
    );
}

def check_mpesa_now -> int {
    # Asks Daraja, then emails the team when M-Pesa looks down and when it's back, and
    # when our own keys are refused and accepted again; how many emails.
    probe_mpesa(now());
    state = mpesa_state(now());
    sent = _flip(
        "mpesa",
        state["likely_down"],
        lambda (to: str) -> any { return mpesa_mail(to, state); }  # jac:ignore[W1037]
    );
    refused = state["our_keys_refused"];
    return sent
        + _flip(
            "mpesa-keys",
            refused,
            lambda (to: str) -> any { return keys_mail(to, refused); }
        );  # jac:ignore[W1037]
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=CHECK_SECONDS)
def check_jobs {
    ran("check_jobs", CHECK_SECONDS);
    check_jobs_now();
    check_mpesa_now();
}

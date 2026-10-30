"""Telling the team when a background job goes silent (P16.2).

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

@schedule(trigger=ScheduleTrigger.STATIC, interval=CHECK_SECONDS)
def check_jobs {
    ran("check_jobs", CHECK_SECONDS);
    check_jobs_now();
}

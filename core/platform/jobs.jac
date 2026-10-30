"""Background jobs checking in (P16.2): which ran, and which have gone quiet.

Every scheduled job calls ran(name, every) first thing: when it ran and how often it's
meant to. A job is **silent** once it hasn't run for SILENT_AFTER of its intervals, and
at least SILENT_MIN_S; one that hasn't checked in since the records began is
**waiting** (just deployed), not silent. The console's overview shows the jobs (job_status), and job_alerts.jac emails
the team when one goes silent and when it runs again.

Kept as one claim per job (JOBS, keyed by name: {"at", "every"}), replaced on each run,
so it's one small write whichever server copy ran it. This module imports nothing but
the clock and the claims, so every job's module can use it.
"""

import json;
import from datetime { datetime, timedelta }
import from core.clock { now }
import from core.claims { claim, holder, take_claim }

glob JOBS: str = "job-ran",
     SILENT_AFTER: int = 3,
     # Never sooner than this: a job that runs every few seconds can lag a little on a
     # busy server without anything being wrong.
     SILENT_MIN_S: int = 300,
     # name: what it does, as the team reads it. Every scheduled job is here.
     KNOWN: dict[str, str] = {
         "send_ticket_mail": "Ticket emails",
         "send_support_mail": "Support emails",
         "send_email_checks": "Email confirmation links",
         "send_decision_mail": "Verification decision emails",
         "send_notices": "Verification notices to owners",
         "send_mpesa_mail": "M-Pesa change emails",
         "sweep_holds": "Releasing expired seat holds",
         "settle_callbacks": "Settling M-Pesa payments",
         "resolve_payments": "Checking unanswered M-Pesa payments",
         "reconcile_payments": "The daily M-Pesa check",
         "check_cash_counted": "Cash not counted",
         "settle_bill_payments": "Settling invoice payments",
         "issue_statements": "Monthly statements",
         "delete_due_files": "Deleting old verification files",
         "delete_due_accounts": "Deleting customer accounts",
         "write_setup_links": "The setup file",
         "check_jobs": "Checking the jobs"
     },
     # Jobs run outside the app, by cron, that check in the same way (P16.5).
     OUTSIDE: dict[str, str] = {"nightly_backup": "The nightly backup"};

def ran(name: str, every: int) {
    # `name` has just run, and runs every `every` seconds.
    take_claim(JOBS, name);
    claim(JOBS, name, json.dumps({"at": now().isoformat(), "every": int(every)}));
}

def last_run(name: str) -> dict[str, any] | None {  # jac:ignore[W1037]
    kept = holder(JOBS, name);
    return json.loads(kept) if kept else None;
}

def job_status(at: datetime) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Each known job: its label, when it last ran, and "running", "silent" or "waiting".
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for (name, label) in [*KNOWN.items(), *OUTSIDE.items()] {
        found = last_run(name);
        state = "waiting";
        if found is not None {
            late = at - datetime.fromisoformat(found["at"]);
            state = "silent"
                if late
                    > timedelta(
                        seconds=max(SILENT_MIN_S, SILENT_AFTER * max(1, found["every"]))
                    )
                else "running";
        }
        rows.append(
            {
                "name": name,
                "label": label,
                "state": state,
                "last_ran": found["at"] if found is not None else ""
            }
        );
    }
    return rows;
}

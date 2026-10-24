"""Deleting personal files once they're no longer needed (P14.5b, ADR-0072).

The periods were decided with the owner on 2026-10-24 (Kenya's Data Protection Act,
2019: kept no longer than needed), and the Verification page's notice says the same:
- **ID photos** (front and back): deleted ID_DAYS after the cinema's verification was
  approved. The approval's date stays, as the record that the ID was checked.
- **Business documents** (registration certificate, KRA PIN certificate, county permit):
  kept while the cinema is on AfriCinemas, deleted DOCS_DAYS after it began closing.
- **Support screenshots**: deleted SCREENSHOT_DAYS after their request was closed; the
  written conversation stays.

retention_due(at) does all three for every cinema, as of `at`; the job runs it every
RETENTION_SECONDS on every server copy. Deleting is idempotent, so two copies running
at once only find less to do. Each deletion is noted where the file was (when it went).
"""

import os;
import from datetime { datetime, timedelta }
import from core.claims { claims_in }
import from core.clock { now }
import from core.tenancy.registry { SLUG_NAMESPACE }
import from core.tenancy.open_cinema { tenant_by_id }
import from core.tenancy.verification { record_of, remove_files }
import from core.support.requests { drop_old_screenshots }

glob ID_DAYS: int = 90,
     DOCS_DAYS: int = 365,
     SCREENSHOT_DAYS: int = 90,
     ID_FILES: list[str] = ["id_front", "id_back"],
     BUSINESS_FILES: list[str] = [
         "registration_certificate",
         "kra_certificate",
         "county_permit"
     ],
     RETENTION_SECONDS: int = int(
         os.environ.get("AFRICINEMAS_RETENTION_SECONDS", "21600")
     );

def _older(stamp: str, at: datetime, days: int) -> bool {
    # Whether the ISO time `stamp` is at least `days` before `at`.
    if not stamp {
        return False;
    }
    try {
        return at - datetime.fromisoformat(stamp) >= timedelta(days=days);
    } except ValueError {
        return False;
    }
}

def retention_due(at: datetime) -> dict[str, int] {
    # Deletes everything due as of `at`; how many of each kind went.
    done = {"id_photos": 0, "business_documents": 0, "screenshots": 0};
    stamp = at.isoformat();
    screenshots_before = (at - timedelta(days=SCREENSHOT_DAYS)).isoformat();
    for (_, tenant_id, _) in claims_in(SLUG_NAMESPACE) {
        cinema = tenant_by_id(str(tenant_id));
        if cinema is None {
            continue;
        }
        kept = record_of(cinema);
        if kept["status"] == "approved" and _older(kept["approved_at"], at, ID_DAYS) {
            done["id_photos"] += remove_files(cinema, ID_FILES, stamp);
        }
        if _older(cinema.closed_at, at, DOCS_DAYS) {
            done["business_documents"] += remove_files(cinema, BUSINESS_FILES, stamp);
        }
        done["screenshots"] += drop_old_screenshots(cinema, screenshots_before, stamp);
    }
    return done;
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=RETENTION_SECONDS)
def delete_due_files {
    # Runs as Jac's system identity on every server copy.
    found = retention_due(now());
    if any([n > 0 for n in found.values()]) {
        print(f"retention: deleted {found}");
    }
}

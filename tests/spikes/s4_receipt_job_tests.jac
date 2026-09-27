"""Spike S4 (plan P1.3): pass criteria for anonymous receipts processed by a system job.

From docs/architecture.md §138 S4: can an anonymous `def:pub` request (M-Pesa callback,
guest checkout) write a record that a system-identity worker later processes? The
scheduler only runs in a served process, so this boots a real server from a temp
project (tests/spikes/s4_app.jac as main.jac, the scheduler on) and drives it over HTTP.
"""

import os;
import shutil;
import tempfile;
import from pathlib { Path }
import from uuid { UUID }
import from tests.support.real_server { RealServer, wait_until, remove_project }

glob REPO_ROOT: Path = Path(__file__).resolve().parent.parent.parent,
     SPIKE_TOML: str = """[project]
name = "s4-spike"
version = "0.1.0"
default-app = "api"

[apps.api]
kind = "service"
entry-point = "main"

[scale.scheduler]
enabled = true
""",
     SYSTEM_ROOT: str = "00000000-0000-0000-0000-000000000000";

def _project -> str {
    # A throwaway project: the spike app, the tenancy module, and the repo's venv
    # (it already holds apscheduler, installed by `jac install` for [scale.scheduler]).
    workdir = tempfile.mkdtemp(prefix="africinemas-s4-");
    shutil.copy(
        REPO_ROOT / "tests" / "spikes" / "s4_app.jac", Path(workdir) / "main.jac"
    );
    shutil.copytree(REPO_ROOT / "core", Path(workdir) / "core");
    (Path(workdir) / "jac.toml").write_text(SPIKE_TOML);
    (Path(workdir) / ".jac").mkdir();
    os.symlink(REPO_ROOT / ".jac" / "venv", Path(workdir) / ".jac" / "venv");
    return workdir;
}

test "an anonymous receipt becomes tenant-owned data through a system job" {
    workdir = _project();
    server = RealServer(workdir=workdir, env=dict(os.environ));
    try {
        server.start();
        owner = server.register("owner_a");
        stranger = server.register("owner_b");
        tenant = server.call("s4_create_tenant", {"name": "Nova"}, owner);
        receipt = {
            "tenant_id": tenant["tenant_id"],
            "reference": "QKA1",
            "amount": 1200
        };

        # 1. Anonymous callback accepted; a retried callback is recognised, not duplicated.
        first = server.call("s4_record_receipt", receipt);
        again = server.call("s4_record_receipt", receipt);
        assert first["accepted"] and not first["duplicate"] , first;
        assert again["duplicate"]
            and again["receipt_id"] == first["receipt_id"] , again;

        # 2. Anonymous callers can't see or change receipts, even holding the id.
        rid = {"receipt_id": first["receipt_id"]};
        assert server.call("s4_peek_receipt", rid) == {"resolved": False};
        assert server.call("s4_tamper_receipt", rid) == {"resolved": False};

        # 3. The scheduled job turns it into a Payment owned by the tenant's principal.
        paid = lambda -> bool { return len(server.call("s4_owner_payments", {}, owner))
            == 1; };
        assert wait_until(paid, 30) , f"not processed; log:\n{server.log()[-2000:]}";
        payment = server.call("s4_owner_payments", {}, owner)[0];
        assert (payment["reference"], payment["amount"]) == ("QKA1", 1200) , payment;
        assert str(UUID(payment["owner"]))
            == str(UUID(tenant["principal_root_id"])) , payment;
        assert payment["level"] == "READ" , "the owner reads it by grant";
        assert server.call("s4_owner_payments", {}, stranger) == [];

        # 4. The job ran as Jac's system identity, and re-running it changes nothing.
        info = server.call("s4_processor_info", {}, owner);
        assert info["last_run_root"] == SYSTEM_ROOT == info["system_root"] , info;
        runs = info["runs"];
        assert wait_until(
            lambda -> bool { return server.call("s4_processor_info", {}, owner)["runs"]
                >= runs + 2; },
            15
        );
        assert len(server.call("s4_owner_payments", {}, owner)) == 1 , "idempotent re-runs";

        # 5. A receipt for an unknown tenant is rejected, not turned into data.
        server.call(
            "s4_record_receipt",
            {"tenant_id": str(UUID(int=7)), "reference": "QKA2", "amount": 500}
        );
        rejected = lambda -> bool { return any(
            r["reference"] == "QKA2" and r["status"] == "rejected"
            for r in server.call("s4_processor_info", {}, owner)["receipts"]
        ); };
        assert wait_until(rejected, 30) , server.call("s4_processor_info", {}, owner);

        # 6. It all persists: after a restart the payment and receipt states are intact.
        server.stop();
        server.start();
        owner = server.login("owner_a");
        payments = server.call("s4_owner_payments", {}, owner);
        assert [(p["reference"], p["amount"]) for p in payments]
            == [("QKA1", 1200)] , payments;
        states = {
            r["reference"]: r["status"]
            for r in server.call("s4_processor_info", {}, owner)["receipts"]
        };
        assert states == {"QKA1": "processed", "QKA2": "rejected"} , states;
    } finally {
        server.stop(drop=True);
        remove_project(workdir);
    }
}

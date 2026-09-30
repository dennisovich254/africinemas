"""Spike S4 (plan P1.3): an anonymous request records a receipt; a scheduled job run by
Jac's system identity turns it into tenant-owned data.

Test-only app, served for real by s4_receipt_job_tests.jac (the scheduler only runs in a
served process). Flow:
- `s4_record_receipt` is `def:pub` (anonymous, like an M-Pesa callback). It briefly acts
  as the system root to append a Receipt to a system-owned Inbox, so no anonymous
  caller can read or alter receipts afterwards. It is idempotent on the reference
  (callbacks are retried).
- `s4_process_receipts` is a static `@schedule` task. Jac runs static tasks as the
  system identity (the system root). For each new receipt it acts as the tenant's
  principal (ADR-0003) to create the Payment, grants it to the owner, and marks the
  receipt processed. Re-running it is harmless, as it must be: every replica fires it.
"""

import from uuid { UUID }
import from jaclang { JacRuntime as Jac }
import from core.tenancy.principal {
    node_id,
    owner_id,
    access_level,
    new_principal,
    act_as,
    system_root_id,
    restore,
    flush_now
}

node Tenant {
    has name: str,
        principal_root_id: str = "",
        owner_root_id: str = "";
}

node Inbox {
    has runs: int = 0,
        last_run_root: str = "";
}

node Receipt {
    has tenant_id: str,
        reference: str,
        amount: int,
        status: str = "new",
        payment_id: str = "";
}

node Payment {
    has reference: str,
        amount: int;
}

edge OwnsTenant {}

edge HasPayment {}

def _inbox -> Inbox {
    # Call while acting as the system root: the inbox hangs off it. Made on first use,
    # which can race with the scheduled job and leave two (graph find-or-create,
    # JI-024), so the one with the smallest id is always picked; production code uses
    # an atomic claim instead (ADR-0007).
    found = [root-->[?:Inbox]];
    if found {
        return sorted(found, key=lambda (b: Inbox) -> str { return node_id(b); })[0];
    }
    box = Inbox();
    root ++> box;
    return box;
}

def _receipts -> list[Receipt] {
    # Every receipt, in whichever inbox it landed (see _inbox).
    return [r for box in [root-->[?:Inbox]] for r in [box-->[?:Receipt]]];
}

def:priv s4_create_tenant(name: str) -> dict[str, str] {
    caller = node_id(root);
    principal = new_principal(name);
    act_as(principal);
    try {
        tenant = Tenant(name=name, principal_root_id=principal, owner_root_id=caller);
        root ++> tenant;
        Jac.allow_root(tenant, UUID(caller), AccessLevel.WRITE);  # jac:ignore[E1053]
        flush_now();
    } finally {
        restore(caller);
    }
    root +>:OwnsTenant:+> tenant;
    return {"tenant_id": node_id(tenant), "principal_root_id": principal};
}

def:pub s4_record_receipt(
    tenant_id: str, reference: str, amount: int
) -> dict[str, any] {
    if not reference or amount <= 0 {
        return {"accepted": False};
    }
    caller = node_id(root);
    act_as(system_root_id());
    try {
        box = _inbox();
        for r in _receipts() {
            if r.reference == reference {
                return {"accepted": True, "receipt_id": node_id(r), "duplicate": True};
            }
        }
        receipt = Receipt(tenant_id=tenant_id, reference=reference, amount=amount);
        box ++> receipt;
        flush_now();
        return {"accepted": True, "receipt_id": node_id(receipt), "duplicate": False};
    } finally {
        restore(caller);
    }
}

@schedule(trigger=ScheduleTrigger.STATIC, interval=1)
def s4_process_receipts {
    job_root = node_id(root);
    box = _inbox();
    box.runs += 1;
    box.last_run_root = job_root;
    for r in _receipts() {
        if r.status != "new" {
            continue;
        }
        found: any = jobj(r.tenant_id);  # jac:ignore[W1037]
        if found is None {
            r.status = "rejected";
            continue;
        }
        tenant = found as Tenant;
        flush_now();
        act_as(tenant.principal_root_id);
        try {
            payment = Payment(reference=r.reference, amount=r.amount);
            tenant +>:HasPayment:+> payment;
            Jac.allow_root(payment, UUID(tenant.owner_root_id), AccessLevel.READ);  # jac:ignore[E1053]
            flush_now();
        } finally {
            restore(job_root);
        }
        r.status = "processed";
        r.payment_id = node_id(payment);
    }
}

def:priv s4_owner_payments -> list[dict[str, any]] {
    return [
        {
            "reference": p.reference,
            "amount": p.amount,
            "owner": owner_id(p),
            "principal": t.principal_root_id,
            "level": access_level(p)
        } for t in [root->:OwnsTenant:->[?:Tenant]]
        for p in [t->:HasPayment:->[?:Payment]]
    ];
}

def:pub s4_peek_receipt(receipt_id: str) -> dict[str, any] {
    # What an anonymous caller holding a receipt id can see or do.
    found: any = jobj(receipt_id);  # jac:ignore[W1037]
    if found is None {
        return {"resolved": False};
    }
    return {
        "resolved": True,
        "can_read": Jac.check_read_access(found.__jac__),
        "can_write": Jac.check_write_access(found.__jac__)
    };
}

def:pub s4_tamper_receipt(receipt_id: str) -> dict[str, any] {
    found: any = jobj(receipt_id);  # jac:ignore[W1037]
    if found is None {
        return {"resolved": False};
    }
    (found as Receipt).amount = 1;
    return {"resolved": True};
}

def:priv s4_processor_info -> dict[str, any] {
    # Test-only look at the inbox, read as the system root.
    caller = node_id(root);
    act_as(system_root_id());
    try {
        box = _inbox();
        return {
            "runs": box.runs,
            "last_run_root": box.last_run_root,
            "system_root": system_root_id(),
            "receipts": [
                {"reference": r.reference, "amount": r.amount, "status": r.status}
                for r in _receipts()
            ]
        };
    } finally {
        restore(caller);
    }
}

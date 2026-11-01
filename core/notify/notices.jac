"""Notices in the back office (owner, 2026-11-01): the bell, and the sidebar's badges.

An event worth telling a cinema's staff about posts a notice (post_notice): what
happened, the back-office section it's about, and the permission whoever should see it
holds. So a new statement goes to who reads the reports, a verification decision to
the owner. Kinds today: a statement issued and the reminders about it (billing), a
verification decision (verification), a reply from AfriCinemas (help), and something
that doesn't add up in the cash or M-Pesa (reconciliation).

Each member has their own read state, one claim per member (READS): what they read,
and when they last marked everything read. Until they mark anything, that time is when
they joined the cinema, so a new member isn't greeted by the cinema's old news and
nothing posted since they joined is missed. Notices older than
KEEP_DAYS aren't shown, and at most SHOWN at a time.

Posting never fails the work that posts it: a notice that can't be written is logged.
"""

import json;
import logging;
import from datetime { timedelta }
import from core.clock { now }
import from core.claims { claim, holder, take_claim }
import from core.authz.policy { ROLE_PERMISSIONS }
import from core.authz.context { TenantScope, resolve_context }
import from core.tenancy.models { Tenant }
import from core.tenancy.groups { attach_to_tenant }
import from core.tenancy.membership { records_of }
import from core.tenancy.principal {
    node_id,
    act_as,
    restore,
    flush_now,
    fresh_node_id
}
import from jaclang.runtime.exceptions { WriteConflict }
import from core.catalog.answers { Refused, answer }

glob READS: str = "notice-reads",
     KEYS: str = "notice-key",
     KEEP_DAYS: int = 60,
     SHOWN: int = 50,
     # Ids kept per member beyond the "read before" time; older ones fall away.
     READ_IDS_MAX: int = 200,
     logger: logging.Logger = logging.getLogger(__name__);

node Notice {
    # One thing that happened at the cinema, for the staff who hold `permission`.
    # section: the back-office section it's about ("billing", "help", ...).
    has tenant_id: str,
        kind: str,
        section: str,
        permission: str,
        title: str,
        body: str = "",
        created_at: str = "";
}

def post_notice(
    cinema: Tenant,
    kind: str,
    section: str,
    permission: str,
    title: str,
    body: str = "",
    key: str = ""
) {
    # Posts a notice; with `key`, only once per key and cinema.
    try {
        if key {
            mine = fresh_node_id();
            if claim(KEYS, f"{node_id(cinema)}|{key}", mine) != mine {
                return;
            }
        }
        me = node_id(root);
        act_as(cinema.principal_root_id);
        try {
            n = Notice(
                tenant_id=node_id(cinema),
                kind=kind,
                section=section,
                permission=permission,
                title=title[:200],
                body=body[:500],
                created_at=now().isoformat()
            );
            cinema ++> n;
            attach_to_tenant(n, cinema);
            flush_now();
        } finally {
            restore(me);
        }
    } except WriteConflict as e {
        raise e;
    } except Exception as e {
        logger.warning("notice %s for %s not posted: %s", kind, cinema.slug, e);
    }
}

def _held(scope: TenantScope) -> set[str] {
    allowed: set[str] = set();
    for a in scope.ctx.assignments {
        allowed = allowed | ROLE_PERMISSIONS[a.role];
    }
    return allowed;
}

def _reads_key(scope: TenantScope) -> str {
    return f"{node_id(scope.tenant)}|{scope.ctx.member_root_id}";
}

def _joined(scope: TenantScope) -> str {
    # When the member joined the cinema ("" if it isn't recorded).
    cinema = scope.tenant;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            m.joined_at
            for m in records_of(cinema)
            if m.staff_root_id == scope.ctx.member_root_id and m.joined_at
        ];
    } finally {
        restore(me);
    }
    return min(found) if found else "";
}

def _reads(scope: TenantScope) -> dict[str, any] {  # jac:ignore[W1037]
    # {"before": iso, "ids": [...]}; until the member marks anything, from when they
    # joined.
    kept = holder(READS, _reads_key(scope));
    if kept {
        return json.loads(kept);
    }
    return {"before": _joined(scope), "ids": []};
}

def _save_reads(scope: TenantScope, state: dict[str, any]) {  # jac:ignore[W1037]
    k = _reads_key(scope);
    take_claim(READS, k);
    claim(READS, k, json.dumps(state));
}

def _visible(scope: TenantScope) -> list[Notice] {
    # The member's notices, newest first: of the last KEEP_DAYS, for their permissions.
    held = _held(scope);
    since = (now() - timedelta(days=KEEP_DAYS)).isoformat();
    cinema = scope.tenant;
    me = node_id(root);
    act_as(cinema.principal_root_id);
    try {
        found = [
            n
            for n in [cinema-->[?:Notice]]
            if n.permission in held and n.created_at >= since
        ];
    } finally {
        restore(me);
    }
    found.sort(key=lambda (n: Notice) -> str { return n.created_at; }, reverse=True);
    return found[:SHOWN];
}

def _unread(n: Notice, reads: dict[str, any]) -> bool {  # jac:ignore[W1037]
    return n.created_at > reads["before"] and node_id(n) not in reads["ids"];
}

def _answer_for(scope: TenantScope) -> dict[str, any] {  # jac:ignore[W1037]
    reads = _reads(scope);
    shown = _visible(scope);
    sections: dict[str, int] = {};
    rows: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for n in shown {
        unread = _unread(n, reads);
        if unread {
            sections[n.section] = sections.get(n.section, 0) + 1;
        }
        rows.append(
            {
                "id": node_id(n),
                "kind": n.kind,
                "section": n.section,
                "title": n.title,
                "body": n.body,
                "created_at": n.created_at,
                "read": not unread
            }
        );
    }
    return {
        "ok": True,
        "notices": rows,
        "unread": sum(sections.values()),
        "sections": sections
    };
}

def _my_notices(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    return _answer_for(resolve_context(tenant));
}

def _read_notices(
    tenant: str, ids: list[str], section: str, everything: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    # Marks notices read: `ids`, every notice of `section`, or everything.
    if not isinstance(ids, list) or not isinstance(everything, bool) {
        raise Refused("invalid_request", "Choose the notices to mark as read.");
    }
    scope = resolve_context(tenant);
    reads = _reads(scope);
    if everything {
        reads = {"before": now().isoformat(), "ids": []};
    } else {
        shown = _visible(scope);
        picked = [
            node_id(n)
            for n in shown
            if node_id(n) in [str(i) for i in ids] or (section and n.section == section)
        ];
        kept = [
            i
            for i in reads["ids"]
            if i in [node_id(n) for n in shown]
        ];
        reads = {
            "before": reads["before"],
            "ids": (
                kept
                + [
                    i
                    for i in picked
                    if i not in kept
                ]
            )[-READ_IDS_MAX:]
        };
    }
    _save_reads(scope, reads);
    return _answer_for(scope);
}

def:protect my_notices(tenant: str) -> dict[str, any] {  # jac:ignore[W1037]
    # The caller's notices, unread counts in all and by section. No shift needed.
    return answer(lambda -> any { return _my_notices(tenant); });  # jac:ignore[W1037]
}

def:protect read_notices(
    tenant: str, ids: list[str], section: str, everything: bool
) -> dict[str, any] {  # jac:ignore[W1037]
    # Every argument is required (JI-060: an omitted default arrives as text).
    return answer(
        lambda -> any { return _read_notices(tenant, ids, section, everything); }  # jac:ignore[W1037]
    );
}

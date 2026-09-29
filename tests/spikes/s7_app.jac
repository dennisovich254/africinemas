"""Spike S7 (plan P3.5b): a cinema's public storefront projection on the shared guest graph.

Test-only app, served for real by s7_storefront_projection_tests.jac (outside a served
process there are no separate users, so root.shared would just be the caller's root).
Question: can staff code, acting as a cinema's principal (ADR-0003), write a Storefront
on `root.shared` that anonymous visitors can read but not change?
- `s7_publish` (logged in): as a new principal, hangs a Storefront off root.shared and a
  ShowItem off it, and grants both READ to everyone (`grant`).
- `s7_read` (anonymous or logged in): reads the Storefront by id and lists its items.
- `s7_tamper` / `s7_attach` (anonymous): try to change the Storefront or hang a node off
  it; the read afterwards shows whether they got through.
- `s7_impostor` / `s7_count_shared` (anonymous): anyone may attach nodes to root.shared
  itself (its floor is CONNECT), so a Storefront found by searching root.shared can't be
  trusted; it has to be reached by the id the cinema recorded.
"""

import from core.tenancy.principal {
    node_id,
    owner_id,
    new_principal,
    act_as,
    restore,
    flush_now
}

node Storefront {
    has name: str;
}

node ShowItem {
    has title: str;
}

def:priv s7_publish(name: str) -> dict[str, str] {
    me = node_id(root);
    principal = new_principal(f"s7-{name}");
    act_as(principal);
    try {
        storefront = Storefront(name=name);
        root.shared ++> storefront;
        grant(storefront, level=AccessLevel.READ);
        item = ShowItem(title="Rafiki 19:30");
        storefront ++> item;
        grant(item, level=AccessLevel.READ);
        flush_now();
    } finally {
        restore(me);
    }
    return {
        "storefront_id": node_id(storefront),
        "owner": owner_id(storefront),
        "principal": principal,
        "shared_root": node_id(root.shared)
    };
}

def:pub s7_read(storefront_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    found: any = jobj(storefront_id);  # jac:ignore[W1037]
    if found is None {
        return {"found": False};
    }
    items = [found-->[?:ShowItem]];
    return {
        "found": True,
        "name": found.name,
        "items": sorted([i.title for i in items]),
        "reader_root": node_id(root)
    };
}

def:pub s7_tamper(storefront_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    found: any = jobj(storefront_id);  # jac:ignore[W1037]
    found.name = "Hacked";
    return {"tried": True};
}

def:pub s7_attach(storefront_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    found: any = jobj(storefront_id);  # jac:ignore[W1037]
    (found as Storefront) ++> ShowItem(title="spam");
    return {"tried": True};
}

def:pub s7_impostor(name: str) -> dict[str, str] {
    fake = Storefront(name=name);
    root.shared ++> fake;
    grant(fake, level=AccessLevel.READ);
    return {"storefront_id": node_id(fake)};
}

def:pub s7_count_shared -> dict[str, any] {  # jac:ignore[W1037]
    return {"names": sorted([s.name for s in [root.shared-->[?:Storefront]]])};
}

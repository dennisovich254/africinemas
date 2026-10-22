"""Snack stock for an order (P12.7; ADR-0052): set aside when the order is placed, sold
when it's paid, given back when it ends unpaid.

Only variants that track stock and stop selling at zero are counted (others always
sell). An order's units come from its priced snack lines (core/snacks/menu.jac), each
line's variant and each combo choice times the line's quantity. What was set aside is
kept on the order ([{variant_id, quantity}]), so selling or giving back uses exactly that.
"""

import logging;
import from core.tenancy.models { Tenant }
import from core.catalog.answers { Refused }
import from core.snacks.store { find_any_variant, find_product }
import from core.snacks.inventory_api {
    rules_of,
    reserve_stock,
    commit_stock,
    release_stock
}
import from core.snacks.menu { snack_name }

glob logger = logging.getLogger(__name__);

def units_of(lines: list[dict[str, any]]) -> dict[str, int] {  # jac:ignore[W1037]
    # Units of each variant the lines take, combo components included.
    needed: dict[str, int] = {};
    for line in lines {
        quantity: int = line["quantity"];
        vid: str = line["variant_id"];
        needed[vid] = needed.get(vid, 0) + quantity;
        for c in line.get("choices", []) {
            needed[c["variant_id"]] = needed.get(c["variant_id"], 0) + quantity;
        }
    }
    return needed;
}

def release_snacks(tenant: Tenant, venue_id: str, held: list[dict[str, any]]) {  # jac:ignore[W1037]
    for h in held {
        release_stock(tenant, h["variant_id"], venue_id, h["quantity"]);
    }
}

def reserve_snacks(
    tenant: Tenant,
    venue_id: str,
    lines: list[dict[str, any]]  # jac:ignore[W1037]
) -> list[dict[str, any]] {  # jac:ignore[W1037]
    # Sets aside the counted units; refuses (snacks_unavailable), giving back what it
    # took, when one has sold out since the cart was priced.
    held: list[dict[str, any]] = [];  # jac:ignore[W1037]
    for (vid, quantity) in units_of(lines).items() {
        variant = find_any_variant(tenant, vid);
        if variant is None
            or not variant.track_stock
            or rules_of(variant, venue_id)["at_zero"] == "allow" {
            continue;
        }
        if not reserve_stock(tenant, vid, venue_id, quantity) {
            release_snacks(tenant, venue_id, held);
            product = find_product(tenant, variant.product_id);
            name = snack_name(product, variant) if product is not None else "A snack";
            raise Refused(
                "snacks_unavailable",
                f"{name} just sold out. Change your snacks and try again."
            );
        }
        held.append({"variant_id": vid, "quantity": quantity});
    }
    return held;
}

def sell_snacks(
    tenant: Tenant,
    venue_id: str,
    held: list[dict[str, any]],  # jac:ignore[W1037]
    order_reference: str
) {
    # The set-aside units leave the shelf, each recorded as a sale of the order. Called
    # inside confirm_order's commit, so the movements are saved with the paid order.
    for h in held {
        if not commit_stock(
            tenant, h["variant_id"], venue_id, h["quantity"], order_reference
        ) {
            # The order is paid either way; the Stock page shows the count to correct.
            logger.warning(
                "snack stock: couldn't sell %s of %s for order %s",
                h["quantity"],
                h["variant_id"],
                order_reference
            );
        }
    }
}

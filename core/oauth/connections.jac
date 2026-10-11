"""Connected apps (P8.6d): the apps a customer has let book for them, and ending one.

Each app a customer signs in at a cinema (Claude, through our OAuth provider) is a
connection with its own chat account (state.jac, accounts.jac). On the cinema's
storefront the customer lists them (my_connected_apps) and disconnects one
(disconnect_app): its connection ends and its chat account is deleted, so its access
token stops working at once and its refresh tokens are refused; other apps keep
working. Only the cinema's own customer account, for its own connections; anyone else
is refused like every storefront account page (require_customer_of). ADR-0035.
"""

import from core.catalog.answers { answer }
import from core.authz.context { NotFound }
import from core.tenancy.principal { node_id }
import from core.tenancy.storefront_accounts { require_customer_of }
import from core.oauth.state { connections_of, end_connection }
import from core.oauth.accounts { delete_chat_account }

def _apps(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_customer_of(slug);
    me = node_id(root);
    return {
        "ok": True,
        "apps": [
            {
                "app_id": client_id,
                "name": found["name"],
                "connected_at": found["connected_at"]
            }
            for (client_id, found) in connections_of(me)
            if found.get("slug") == slug
        ]
    };
}

def _disconnect(slug: str, app_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    require_customer_of(slug);
    ended = end_connection(node_id(root), app_id) if app_id else None;
    if ended is None {
        raise NotFound();
    }
    delete_chat_account(ended["user_id"]);
    return {"ok": True};
}

def:priv my_connected_apps(slug: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _apps(slug); });  # jac:ignore[W1037]
}

def:priv disconnect_app(slug: str, app_id: str) -> dict[str, any] {  # jac:ignore[W1037]
    return answer(lambda -> any { return _disconnect(slug, app_id); });  # jac:ignore[W1037]
}

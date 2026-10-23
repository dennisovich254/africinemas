"""A back-office link to the cinema's storefront (P14.1).

Once the cinema is live, its storefront's own address. Before then the storefront is
only its team's to see: the link carries a preview pass (storefront_preview), which the
storefront page keeps for its tab (web/preview.jac). Opens in a new tab.
"""

import from react { useState, useEffect }
import from core.tenancy.tenant_api { storefront_preview }  # jac:ignore[W2037] authenticated endpoint
import from ..site { storefront_address }

def:pub StorefrontLink(
    slug: str,
    className: str = "",
    testid: str = "",
    children: any = None  # jac:ignore[W1037] pass-through children
) -> JsxElement {
    [pass_token, set_pass_token] = useState("");
    async def load {
        try {
            answer: any = await storefront_preview(slug);  # jac:ignore[W1037,W2037]
            if answer["ok"] {
                set_pass_token(answer["token"]);
            }
        } except Exception as e {
            console.warn("storefront_preview failed", e);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);
    address = storefront_address(slug);
    return
        <a
            href={address + (f"#preview={pass_token}" if pass_token else "")}
            target="_blank"
            rel="noreferrer"
            className={className}
            data-testid={testid or None}
        >
            {children}
        </a>;
}

"""What customers agree to, where they act (P14.3c, ADR-0068): above Pay, and when
signing up.

AgreeNotice says that paying (or creating an account) is agreeing to the cinema's
published terms and refunds policy, and where to read how their details are used, each
a link opening in a new tab so the checkout isn't lost. No tick box for the terms:
acting is agreeing, and the notice sits beside the button. OffersBox is the one box:
offers from the cinema, never ticked for the customer, shown only when the cinema says
it sends them.
"""

import from react { useState, useEffect }
import from core.catalog.policies { public_policies }
import from .site_info_view { use_site_info }
import from ..site { local_path }

glob AGREED: list[str] = ["terms", "refunds"],
     # How the notice names each policy, in its sentence.
     NAMES: dict[str, str] = {
         "terms": "terms of ticket sale",
         "refunds": "refund policy",
         "privacy": "privacy policy"
     },
     LINK: str = "underline underline-offset-4 hover:text-foreground";

obj Agreement {
    # The cinema's published policies ({kind, title}), and whether it sends offers.
    has policies: list[dict[str, str]] = [],
        sends_offers: bool = False;
}

def:pub use_agreement(slug: str) -> Agreement {
    [pages, set_pages] = useState([]);
    info = use_site_info(slug);
    async def load {
        try {
            answer: any = await public_policies(slug);  # jac:ignore[W1037]
            if answer["ok"] {
                set_pages(answer["policies"]);
            }
        } except Exception as e {
            console.warn("public_policies failed", e);
        }
    }
    def start {
        load();
    }
    useEffect(start, [slug]);
    shown: dict[str, any] = info or {};  # jac:ignore[W1037]
    return Agreement(
        policies=pages, sends_offers=bool(shown["sends_offers"]) if shown else False
    );
}

def PolicyLink(slug: str, page: dict[str, str]) -> JsxElement {
    return
        <a
            href={local_path(f"/c/{slug}/policies/{page['kind']}")}
            target="_blank"
            rel="noreferrer"
            className={LINK}
        >
            {NAMES[page["kind"]] if page["kind"] in NAMES else page["title"]}
        </a>;
}

def:pub AgreeNotice(slug: str, agreement: Agreement, action: str) -> JsxElement {
    # `action`: what the customer does, "paying" or "creating an account".
    agreed = [
        p
        for p in agreement.policies
        if p["kind"] in AGREED
    ];
    privacy = [
        p
        for p in agreement.policies
        if p["kind"] == "privacy"
    ];
    if len(agreed) == 0 and len(privacy) == 0 {
        return <span className="hidden" data-testid="agree-notice"/>;
    }
    return
        <p data-testid="agree-notice" className="text-sm text-muted-foreground">
            {len(agreed) > 0
                and <span>
                    By {action}, you agree to this cinema's {[
                        <span key={p["kind"]}>
                            {i > 0 and " and "}
                            <PolicyLink slug={slug} page={p}/>
                        </span> for (i, p) in enumerate(agreed)
                    ]}.{" "}
                </span>}{len(privacy) > 0
                and <span>
                    Its{" "}
                    <PolicyLink slug={slug} page={privacy[0]}/>{" "}
                    says how your details are used.
                </span>}
        </p>;
}

def:pub OffersBox(
    agreement: Agreement,
    checked: bool,
    on_change: any  # jac:ignore[W1037]
) -> JsxElement {
    if not agreement.sends_offers {
        return <span className="hidden"/>;
    }
    return
        <label
            className="flex min-h-11 cursor-pointer items-center gap-3 text-sm"
            data-testid="offers-box"
        >
            <input
                type="checkbox"
                id="offers"
                className="size-5"
                checked={checked}
                onChange={lambda { on_change(not checked); }}
            />
            Send me this cinema's offers and news by email. You can stop them at any time.
        </label>;
}

def:pub AdultBox(
    checked: bool,
    error: str,
    on_change: any  # jac:ignore[W1037]
) -> JsxElement {
    # "I'm 18 or over", at sign-up and before paying (Data Protection Act s.33, P15.0):
    # AfriCinemas doesn't take children's details. Never ticked for the customer.
    return
        <div className="flex flex-col gap-1">
            <label
                className="flex min-h-11 cursor-pointer items-center gap-3 text-sm"
                data-testid="adult-box"
            >
                <input
                    type="checkbox"
                    id="adult"
                    className="size-5"
                    checked={checked}
                    aria-invalid={"true" if error else "false"}
                    aria-describedby={"adult-error" if error else None}
                    onChange={lambda { on_change(not checked); }}
                />
                I'm 18 or over.
            </label>
            {error
                and <p
                    id="adult-error"
                    role="alert"
                    className="text-sm text-destructive"
                >
                    {error}
                </p>}
        </div>;
}

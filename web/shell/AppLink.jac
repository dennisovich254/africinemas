"""A typed in-app link (P3.7a).

The router's `Link` has no type information, so the checker reports every use of it
(W1051). Pages link through AppLink instead; the one untyped use is here. Inside a
`Button asChild` the button's classes arrive through `className`; a test id that must
be on the link itself is passed as `testid` (P3.9), and `current` marks the link to the
page being shown (aria-current, P4.1b).
"""

import from "@jac/runtime" { Link }

def:pub AppLink(
    to: str,
    className: str = "",
    testid: str = "",
    current: bool = False,
    children: any = None  # jac:ignore[W1037] pass-through children (jac-cl-organization idiom)
) -> JsxElement {
    return
        <Link
            to={to}
            className={className}
            data-testid={testid or None}
            aria-current={"page" if current else None}
        >
            {children}
        </Link>;
}

"""A typed in-app link (P3.7a).

The router's `Link` has no type information, so the checker reports every use of it
(W1051). Pages link through AppLink instead; the one untyped use is here.
"""

import from "@jac/runtime" { Link }

def:pub AppLink(
    to: str,
    className: str = "",
    children: any = None  # jac:ignore[W1037] pass-through children (jac-cl-organization idiom)
) -> JsxElement {
    return <Link to={to} className={className}>{children}</Link>;
}

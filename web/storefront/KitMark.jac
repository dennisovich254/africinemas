"""The cinema's motif, worn inside the storefront's parts (ADR-0046).

A KitMark is an empty, decorative span. styles/brandkit.css paints it with the theme's
primary colour through the cinema's motif mask (--kit-single or --kit-group on the
storefront root), and hides it when the cinema has no motif. Marks carry no meaning, so
screen readers skip them.
"""

def:pub KitMark(kind: str = "single", className: str = "") -> JsxElement {
    return <span aria-hidden="true" data-kit-mark={kind} className={className}></span>;
}

def:pub KitDivider -> JsxElement {
    # Between home sections: one motif in a line, a row of three, or a plain line, as the
    # cinema's look says; nothing without a kit.
    return
        <div aria-hidden="true" data-kit-divider-slot="on">
            <KitMark/>
            <KitMark/>
            <KitMark/>
        </div>;
}

"""Sticky bottom action bar (P0.8c), e.g. "2 seats · KES 1,200 [Continue]".

Place it as the last item of a full-height flex column (AppShell's `actions` does this).
It sticks to the bottom of the viewport while content scrolls under it, sits after the
content at the end (so it never covers the last item), and pads for the phone's home
indicator via the safe-area inset.
"""

# `children: any` is the documented idiom for pass-through children (jac-cl-organization).
def:pub BottomActionBar(label: str = "Actions", children: any = None) -> JsxElement {  # jac:ignore[W1037]
    return
        <div
            role="region"
            aria-label={label}
            data-testid="bottom-action-bar"
            className="sticky bottom-0 z-20 border-t bg-card px-4 pt-3 pb-[max(env(safe-area-inset-bottom),0.75rem)] lg:px-8"
        >
            <div className="mx-auto flex w-full max-w-5xl items-center gap-3">
                {children}
            </div>
        </div>;
}

"""Design tokens and the StyleSheet for mobile.

Tokens are `obj` types instantiated once into typed globals, so `C.accent`,
`S.lg`, `R.pill` and `F.md` are attribute reads the compiler checks. The palette
mirrors the storefront dark tokens (core/theming/tokens.jac DEFAULT_THEME.dark);
tests/unit/mobile_theme_sync_tests.jac keeps them in sync. `styles` is a React Native
StyleSheet: the same objects work on the web (react-native-web) and on native.
"""

import from "@jac/mobui" { StyleSheet }

obj Palette {
    has bg: str = "#0F0C09",
        surface: str = "#1C1712",
        border: str = "#3F342A",
        field: str = "#27201A",
        text: str = "#F7F1E8",
        muted: str = "#BDAE9A",
        accent: str = "#E7B03A",
        onAccent: str = "#1A1203",
        danger: str = "#F87171";
}

obj Spacing {
    has xs: int = 4,
        sm: int = 8,
        md: int = 12,
        lg: int = 16,
        xl: int = 24;
}

obj Radius {
    has sm: int = 8,
        md: int = 12,
        lg: int = 16,
        pill: int = 999;
}

obj FontSize {
    has sm: int = 14,
        md: int = 16,
        lg: int = 20,
        xl: int = 28;
}

glob:pub C: Palette = Palette(),
     S: Spacing = Spacing(),
     R: Radius = Radius(),
     F: FontSize = FontSize();

glob:pub styles = StyleSheet.create(
         {
             "screen": {"flex": 1, "backgroundColor": C.bg},
             "content": {
                 "width": "100%",
                 "maxWidth": 560,
                 "alignSelf": "center",
                 "padding": S.lg,
                 "gap": S.lg
             },
             "header": {"gap": S.xs, "paddingTop": S.xl},
             "titleRow": {"flexDirection": "row", "alignItems": "center", "gap": S.sm},
             "title": {"color": C.text, "fontSize": F.xl, "fontWeight": "bold"},
             "subtitle": {"color": C.muted, "fontSize": F.sm},
             "composer": {"flexDirection": "row", "alignItems": "center", "gap": S.sm},
             "input": {
                 "flex": 1,
                 "color": C.text,
                 "fontSize": F.md,
                 "backgroundColor": C.field,
                 "borderWidth": 1,
                 "borderColor": C.border,
                 "borderRadius": R.md,
                 "paddingVertical": S.md,
                 "paddingHorizontal": S.lg
             },
             "list": {"gap": S.sm},
             "row": {
                 "flexDirection": "row",
                 "alignItems": "center",
                 "gap": S.md,
                 "backgroundColor": C.surface,
                 "borderWidth": 1,
                 "borderColor": C.border,
                 "borderRadius": R.lg,
                 "paddingVertical": S.md,
                 "paddingHorizontal": S.lg
             },
             "rowText": {"flex": 1, "color": C.text, "fontSize": F.md},
             "empty": {"alignItems": "center", "gap": S.sm, "paddingVertical": S.xl},
             "emptyText": {"color": C.muted, "fontSize": F.sm, "textAlign": "center"}
         }
     );

# JI-009: Freshly scaffolded templates produce ~130 `jac check` warnings

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-26, P0.2
- **Status:** open (noise, not a bug in behaviour)

## Behaviour
Straight after `jac create --use jac-shadcn` plus `--app desktop --kind desktop` and `--app mobile --kind mobile`, `jac check` passes but emits ~130 warnings, all in generated files. For example, `mobile/theme.jac` and `mobile/components/Button.jac` use unquoted dict keys (`{color: ...}`), giving 71× W2001 "Name may be undefined". `components/ui/*.jac` (shadcn primitives) also give W1037/W1051.

## Workaround
Treat vendored/generated files as a warning baseline and ratchet it (plan P0.4) instead of hand-editing `components/ui/`, which `jac install --shadcn` manages.

# JI-019: A workspace's mobile app pins React 18 for every app, silently undoing the React 19 `ref` fix

- **Version:** jaclang 0.37.18 (jac-client from the same release)
- **Found:** 2026-09-27, P0.8c (an e2e test: closing a shadcn `Sheet` with Escape did not return focus to its trigger)
- **Status:** open (worked around in our `jac.toml`)

## What we saw
- `jac create --app mobile --kind mobile` (our P0.2 scaffold, commit `105cd31`) wrote:
  ```toml
  [apps.mobile.dependencies.npm]
  react = "^18.2.0"
  react-dom = "^18.2.0"
  react-native-web = "^0.19.13"   # peer-requires react ^18
  ```
- The workspace apps (`web`, `desktop`, `mobile`) appear to share **one** install: `.jac/client/configs/package.json` listed only `"react": "^18.2.0"`, and `.jac/client/node_modules/react` was **18.3.1**. So the web and desktop apps ran on React 18 too.
- The jaclang release notes say the client runtime moved to React 19 so a `props`-bundle component (like the installed shadcn `Button`) receives `ref`, which fixes Radix `asChild` triggers. They add that a project which pinned React by hand keeps its pin. Here, as far as we can tell, the pin was written by the mobile template, not by hand.
- Effect under React 18: `<SheetTrigger asChild={True}><Button …/></SheetTrigger>`. The `ref` is dropped at the Jac `Button`, Radix's `triggerRef` stays null, and on close focus falls to `<body>` instead of the trigger. We confirmed this with Playwright: `document.activeElement` was `BODY` after Escape, and the trigger never got a ref. The `jac-shadcn-components` guide warns that the same missing ref makes popovers and menus open at the viewport origin. Nothing in the build or `jac check` warns.

## Workaround (in place)
Bump the mobile pins in `jac.toml` to `react`/`react-dom` `^19.2.0` and `react-native-web` `^0.21.2` (its peers allow `^18 || ^19`). After `jac install`, React is 19.3.0 for all apps and focus returns to the trigger (e2e `the phone drawer opens, closes with Escape and returns focus`).

## Possible improvements (suggestions, we may be missing context)
- The mobile template could pin React 19 and `react-native-web` ≥ 0.21, matching the core runtime.
- Or the workspace install could warn when one app's pin downgrades a core runtime dependency that the other apps rely on.

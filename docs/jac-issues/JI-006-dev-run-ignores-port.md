# JI-006: `jac run <web-app>` (dev mode) appears to ignore `--port`

- **Version:** jaclang 0.37.18
- **Found:** 2026-09-26, P0.2
- **Status:** open (I may be misusing the flag for dev mode)

## Behaviour
`jac run web --port 8765` for a `web-app` kind started **dev mode** anyway, with the app on 8000 (Vite) and the API on 8001, and nothing listened on 8765. When 8001 was held by a stale server, the API silently moved to 8002.

## Workaround
Use the defaults (8000/8001) and stop stale servers with `pkill -f "[j]ac run"`.

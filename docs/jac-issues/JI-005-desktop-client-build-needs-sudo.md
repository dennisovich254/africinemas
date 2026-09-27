# JI-005: `jac build desktop --as client` still provisions the native toolchain via `sudo -n apt-get`

- **Version:** jaclang 0.37.18, Ubuntu on WSL2
- **Found:** 2026-09-26, P0.2
- **Status:** open

## Behaviour
Expecting only the client bundle, `jac build desktop --as client` ran for ~9 minutes, then failed with
`CalledProcessError: Command '['/usr/bin/sudo', '-n', '/usr/bin/apt-get', 'update']' returned non-zero exit status 1`.
Packages it wants (`jaclang/toolchains/system.jac`): `g++ pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev`. `sudo -n` can't prompt for a password, so this fails on typical dev machines.

## Workaround
Install the packages once by hand (`sudo apt-get install -y g++ pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev`), or build desktop in CI (passwordless sudo). The ADR-0001 shared-UI design is verified with `jac check --app desktop`.

## Possible improvement (suggestion)
Skip native provisioning for `--as client`, and print the exact `sudo apt-get install ...` command instead of failing late.

#!/usr/bin/env bash
# Prints a join link for each AfriCinemas platform super admin in .env
# (AFRICINEMAS_PLATFORM_ADMINS, plan P13.1b.a): the only way their platform account is
# made, or its forgotten password replaced. Run it on the server, from the repository.
#   scripts/platform_setup.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
. scripts/load_env.sh
jac run scripts/platform_setup.jac 2>&1 | grep -v -e '^Preparing application' -e '^  Compiling'

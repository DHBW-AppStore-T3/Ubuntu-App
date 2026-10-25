#!/bin/sh
# One persistent bash session per name, run by ttyd for every browser connection. Closing the tab only detaches
# (dtach); opening the page again attaches to the same shell, so background jobs and the working directory survive.
# https://<host>/?arg=<name> opens another, independent session: some exercises need two terminals (server and client).
#
# -E: no detach key (Ctrl-\ stays a normal key). -z: Ctrl-Z goes to the shell (exercise 4 uses job control).
set -eu

name=$(printf '%s' "${1:-main}" | tr -cd 'A-Za-z0-9_-' | cut -c1-32)
[ -n "$name" ] || name=main

exec dtach -A "/tmp/ubuntu-app-$name.session" -E -z -r winch /bin/bash -l

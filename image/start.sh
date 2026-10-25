#!/bin/sh
# Start of a terminal pod: seeds the persistent home directory, then serves a web terminal (ttyd) on port 8080.
# No sudo, no root: the platform runs this as an unprivileged user with a read-only root filesystem.
#
# The login is the platform's generated password (env PASSWORD) with the user name from env APP_USER, the same pair
# "Meine Zugänge" shows. Nothing is written outside HOME and /tmp.
set -eu

: "${PASSWORD:?PASSWORD is not set}"
HOME="${HOME:-/home/student}"
export HOME

# The volume mounted at HOME hides what the image put there. Copy what is missing, never overwrite the student's work.
for f in .bashrc .profile .bash_logout; do
    [ -e "$HOME/$f" ] || cp "/etc/skel/$f" "$HOME/$f"
done
if [ ! -e "$HOME/linux-kurs" ]; then
    # Via a temporary name, so that an interrupted copy is not taken for the finished course directory.
    rm -rf "$HOME/.linux-kurs.tmp"
    cp -r /opt/ubuntu-app/linux-kurs "$HOME/.linux-kurs.tmp"
    mv "$HOME/.linux-kurs.tmp" "$HOME/linux-kurs"
fi

# ttyd splits the credential at the first colon.
user=$(printf '%s' "${APP_USER:-student}" | tr -d ':')
[ -n "$user" ] || user=student

cd "$HOME"

# --ipv6: the cluster is IPv6-primary. --url-arg: https://<host>/?arg=<name> opens a second, independent terminal
# (see shell.sh). env -u: the shells must not inherit the password.
exec env -u PASSWORD ttyd --writable --ipv6 --port 8080 --url-arg \
    --credential "$user:$PASSWORD" \
    /usr/local/bin/ubuntu-app-shell

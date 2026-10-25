#!/usr/bin/env bash
# Smoke test: the terminal starts in the platform's security context, asks for the password, opens real shell sessions
# (also a second one, and re-attaching), the toolchain of the VM version (v1.x) is there, and the lecturer's first six
# exercises (man, cat, echo, wc, sort, uniq, head, shell scripts) work without sudo. Run by the central pipeline
# (DHBW-AppStore-T3/app-registry) against the locally built image, before the Trivy scan and before any push.
# IMAGE and PLATFORM_RUN_FLAGS (--user 1000:1000 --read-only --cap-drop ALL --security-opt no-new-privileges
# --network host) come from the pipeline; the pipeline removes the container afterwards.
set -euo pipefail

# /tmp and the volume allow exec in the cluster (emptyDir, PVC); docker's tmpfs does not unless told to.
# shellcheck disable=SC2086  # PLATFORM_RUN_FLAGS is meant to split into words
docker run -d --name term $PLATFORM_RUN_FLAGS \
  --tmpfs /tmp:exec,size=256m --tmpfs /home/student:uid=1000,gid=1000,exec \
  -e PASSWORD=ci-smoke-test -e APP_USER=ci-user \
  "$IMAGE"

# The cluster is IPv6-primary: the terminal must answer on [::1].
ok=0
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null -u ci-user:ci-smoke-test "http://[::1]:8080/"; then ok=1; break; fi
  sleep 2
done
docker logs term
[ "$ok" = 1 ]

# Without the password the terminal must not answer.
code=$(curl -s -o /dev/null -w '%{http_code}' "http://[::1]:8080/")
[ "$code" = 401 ]

# Real sessions over WebSocket: log in, a second independent shell, re-attaching to the first.
TTY_USER=ci-user TTY_PASSWORD=ci-smoke-test python3 .github/test-terminal.py

docker exec -i term bash -s <<'EOF'
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
cd "$HOME"

# The platform's context: UID 1000 with a name and a home that is the volume.
[ "$(id -u)" = 1000 ] || fail "not UID 1000"
[ "$(whoami)" = student ] || fail "user name is $(whoami)"
[ "$HOME" = /home/student ] || fail "HOME is $HOME"

# What the VM version gave the students, and what the reference sheet and the lecturer's exercises use.
for c in python3 pip3 node npm git curl wget tree htop nano vim awk man info less ping ip ps top free df du \
         ttyd dtach openssl; do
  command -v "$c" >/dev/null || fail "missing command: $c"
done
python3 --version; node --version; npm --version; git --version
# GNU coreutils, not the Rust ones Ubuntu 26.04 uses by default: the course and its man pages are GNU.
version=$(cat --version); grep -q 'GNU coreutils' <<<"$version" || fail "cat is not GNU coreutils: $(head -1 <<<"$version")"
version=$(sort --version); grep -q 'GNU coreutils' <<<"$version" || fail "sort is not GNU coreutils"
out=$(python3 -m venv "$HOME/venv" && "$HOME/venv/bin/python" -c 'print("hello-venv")')
[ "$out" = hello-venv ] || fail "python venv"
[ "$(npm config get prefix)" = /home/student/.npm-global ] || fail "npm prefix"

# The course directory is seeded into the (empty) volume, and the shell dotfiles with it.
for f in .bashrc .profile linux-kurs/LIES_MICH.txt linux-kurs/beispieldaten/server.log \
         linux-kurs/beispieldaten/studenten.csv; do
  [ -f "$f" ] || fail "missing $f"
done
for d in 01-navigation 02-dateien 03-berechtigungen 04-prozesse 05-textverarbeitung; do
  [ -f "linux-kurs/uebungen/$d/aufgaben.txt" ] || fail "missing exercise $d"
done
[ -w linux-kurs/LIES_MICH.txt ] || fail "course files are not writable by the student"

# Exercise 1 (man, cat) and 2 (echo, wc). The container image strips man pages unless the Dockerfile restores them.
export TERM=dumb MANPAGER=cat PAGER=cat
page=$(man cat 2>&1 || true)
if ! grep -qi concatenate <<<"$page"; then
  echo "--- man cat printed:"; head -20 <<<"$page"
  echo "--- cat is:"; readlink -f "$(command -v cat)"; dpkg -S "$(readlink -f "$(command -v cat)")" || true
  echo "--- packages:"; dpkg -l | grep -E 'coreutils|findutils|diffutils|man-db|manpages' || true
  echo "--- man is:"; readlink -f "$(command -v man)"; ls -la /usr/share/man/man1/cat.1* || true
  echo "--- man pages of section 1:"; ls /usr/share/man/man1 | wc -l
  fail "man cat"
fi
page=$(man bash 2>&1 || true); grep -q echo <<<"$page" || { head -20 <<<"$page"; fail "man bash"; }
printf 'a\nb\nc\nd\n' | cat > file1
printf 'e\nf\ng\nh\n' | cat > file2
cat file1 file2 | cat -n > file3
[ "$(wc -l < file3)" = 8 ] || fail "task 1: cat -n"
[ "$(echo -e 'Dear friend!\n\n\n Welcome!' | wc -l)" = 4 ] || fail "task 2a: echo -e"
echo > testf; echo >> testf
[ "$(wc testf | awk '{print $1, $2, $3}')" = "2 0 2" ] || fail "task 2b: wc"

# Exercise 3 (sort -uf) and 4 (uniq -ci).
printf 'Mueller fehlt\nMaier fehlt\nSchmidt fehlt\nMaier fehlt\nMueller fehlt\nSchmidt fehlt\nmaier fehlt\nSchmidt fehlt\nMueller fehlt\nschmidt\tfehlt\nmueller FehLt\n' > Namen
[ "$(sort -uf Namen | wc -l)" = 4 ] || fail "task 3: sort -uf"
# Not "| head -n1" inside the pipeline: with pipefail, head closing early can fail the pipeline with SIGPIPE.
counts=$(sort -f Namen | uniq -ci | sort -rn)
top=$(head -n1 <<<"$counts")
[ "$(awk '{print $1}' <<<"$top")" = 4 ] || fail "task 4: uniq -ci ($top)"
grep -q 'Mueller fehlt' <<<"$top" || fail "task 4: most frequent line ($top)"

# Exercise 5 (mydel as "rm" in ~/bin, found through PATH) runs from the volume.
mkdir -p Papierkorb bin
printf '#! /bin/bash\necho Removing $@\nmv $@ $HOME/Papierkorb/\n' > mydel
chmod 755 mydel
cp mydel "$HOME/bin/rm"
export PATH="$HOME/bin:$PATH"
touch t1.txt t2.txt
rm t*.txt
[ -e Papierkorb/t1.txt ] && [ -e Papierkorb/t2.txt ] && [ ! -e t1.txt ] || fail "task 5: mydel"
/bin/rm -r "$HOME"/Papierkorb/*
[ -z "$(ls -A Papierkorb)" ] || fail "task 5: emptying the trash"

# Exercise 6 (read, case): a script that reads names until "q".
cat > quiz.sh <<'SCRIPT'
while (true);
do
    echo -n "Geben Sie bitte den Namen ein: "
    read STUDENT
    case $STUDENT in
        q | quit ) exit;;
    esac
    echo -n "Die Note von $STUDENT ist "
    case $STUDENT in
        carla | hans ) echo "1.0";;
        uta | berta | georg ) echo "4.0";;
        * ) echo "5.0";;
    esac
done
SCRIPT
answers=$(printf 'carla\nberta\nxyz\nq\n' | bash quiz.sh)
grep -q 'Die Note von carla ist 1.0' <<<"$answers" || fail "task 6: carla"
grep -q 'Die Note von berta ist 4.0' <<<"$answers" || fail "task 6: berta"
grep -q 'Die Note von xyz ist 5.0' <<<"$answers" || fail "task 6: other names"

# The adapted exercise 3: a normal user is refused where the exercise says so.
if cat /etc/shadow 2>/dev/null; then fail "exercise 3: /etc/shadow is readable"; fi
if touch /etc/testdatei 2>/dev/null; then fail "exercise 3: /etc is writable"; fi
umask >/dev/null
stat -c '%A %U' linux-kurs >/dev/null

echo "exercises OK"
EOF

docker rm -f term >/dev/null

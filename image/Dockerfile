# Linux terminal for the pod runtime (appstore.yaml): a web terminal (ttyd) with a persistent bash session per
# person. One container per person; the platform sets the user (UID 1000), a read-only root filesystem, the
# password (env PASSWORD) and the user name (env APP_USER). No sudo, no SSH, no root.
FROM docker.io/library/ubuntu:26.04

ARG DEBIAN_FRONTEND=noninteractive

# What the VM version (v1.x, packer/provision.sh and terraform/cloud-init) gave the students: Python with pip and venv,
# Node.js with npm, git, curl, wget, tree, htop, nano, vim, openssl and net-tools. On top of that: what the course
# reference sheet uses (man pages, info, less, ps/top/free, ip, ping), gawk for the lecturer's awk exercise, bash
# completion for the TAB tip, and the terminal itself (ttyd, dtach).
#
# Ubuntu's container image strips the man pages (dpkg path-exclude); the exercises rely on "man cat" and "man bash".
# Packages that are already in the base image have to be reinstalled to get their pages back.
RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion \
        ca-certificates \
        curl \
        dtach \
        gawk \
        git \
        htop \
        info \
        iproute2 \
        iputils-ping \
        less \
        man-db \
        manpages \
        nano \
        net-tools \
        nodejs \
        npm \
        openssl \
        procps \
        python3 \
        python3-pip \
        python3-venv \
        tree \
        ttyd \
        tzdata \
        vim \
        wget \
    && apt-get install -y --reinstall --no-install-recommends \
        bash \
        coreutils \
        diffutils \
        findutils \
        grep \
        sed \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

# The platform runs the pod as UID 1000. The base image may ship a default user with that ID: replace it, so that the
# user has a passwd entry, a name and a home directory.
RUN (userdel -r ubuntu 2>/dev/null || true) \
    && (groupdel ubuntu 2>/dev/null || true) \
    && groupadd -g 1000 student \
    && useradd -m -u 1000 -g 1000 -s /bin/bash student

# The course directory. The persistent volume hides /home/student, so start.sh copies it there at the first start.
COPY kurs/ /opt/ubuntu-app/linux-kurs/
COPY --chmod=0755 start.sh /usr/local/bin/ubuntu-app-start
COPY --chmod=0755 shell.sh /usr/local/bin/ubuntu-app-shell
RUN find /opt/ubuntu-app -type d -exec chmod 755 {} + \
    && find /opt/ubuntu-app -type f -exec chmod 644 {} +

# The root filesystem is read-only; HOME (/home/student) is the persistent volume. So installs land there: pip falls
# back to ~/.local when the system site-packages are not writable (PIP_BREAK_SYSTEM_PACKAGES lifts the PEP 668 refusal
# for that user install), npm -g goes to ~/.npm-global.
ENV HOME=/home/student \
    LANG=C.UTF-8 \
    TZ=Europe/Berlin \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    NPM_CONFIG_PREFIX=/home/student/.npm-global \
    PATH=/home/student/.npm-global/bin:/home/student/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

USER 1000
WORKDIR /home/student
EXPOSE 8080

# start.sh seeds the volume and starts ttyd; it needs neither sudo nor root.
ENTRYPOINT ["/usr/local/bin/ubuntu-app-start"]

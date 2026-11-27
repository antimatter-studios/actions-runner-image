# The image the ARC runner scale sets on antimatter-vps run: ghcr.io/actions/actions-runner plus the
# OS tools GitHub's ubuntu-24.04 image preinstalls and our workflows expect. Everything is installed
# here, at build time, so a runner pod starts run.sh and nothing else. A slow or broken apt mirror
# fails this build instead of a runner: on 2026-11-19 an apt-get update at pod start hung for 8h45m
# and that runner never registered.
#
# No version-pinned toolchains (Go, Node, Rust, Helm): workflows get those from setup-* actions.
#
# The tag is for people; the digest is what is pulled. Dependabot bumps both.
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:6d0b2d80d80f143f77dcb676e50920100bbb547e39e883454d57f45ab8c31300

USER root
ENV DEBIAN_FRONTEND=noninteractive

# The base image is minimised: dpkg drops every package's man pages and /usr/bin/man is a stub
# ("This system has been minimized"). rust-fs-ntfs's docs check runs `man -w 8 mkfs.ntfs`
# (rust-fs-ntfs #1362), so that is undone before anything is installed. man-db's index is not
# built: `man -w` reads the files directly.
# libatomic1: Node 26.x from actions/setup-node exits 127 without it. python3-yaml: rust-fs-core's
# ci-gate.sh and other CI scripts. cpio: rust-fs-bcachefs's kernel-oracle scripts.
# packages.microsoft.com is only for installing powershell here, so its package is purged after,
# which removes the apt source: on 2026-11-27 it answered 403 intermittently, and that failed
# `apt-get update` in jobs that installed nothing from it. A job that wants it adds it itself.
RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes /usr/bin/man \
 && { dpkg-divert --quiet --remove --rename /usr/bin/man || true; } \
 && echo "man-db man-db/auto-update boolean false" | debconf-set-selections \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config libssl-dev libatomic1 cmake clang lld gdb \
      python3 python3-venv python3-yaml \
      ca-certificates gnupg wget curl jq git git-lfs \
      unzip zip rsync file less gzip xz-utils zstd cpio \
      man-db ntfs-3g shellcheck \
 && wget -q -O /tmp/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
 && dpkg -i /tmp/packages-microsoft-prod.deb \
 && rm /tmp/packages-microsoft-prod.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends powershell \
 && dpkg --purge packages-microsoft-prod \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/runner/.local/bin \
 && chown -R runner:runner /home/runner/.local

ENV PATH=/home/runner/.local/bin:$PATH
USER runner

# Fail the build, not a CI job, if a tool is missing.
RUN set -e; export PATH="$PATH:/usr/sbin:/sbin"; \
    for t in cc c++ make cmake clang ld.lld gdb pkg-config python3 pwsh ntfsfix ntfsls ntfscat shellcheck \
             jq git git-lfs curl wget gpg unzip zip rsync file less gzip xz zstd cpio man; do \
      command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; \
    done; \
    printf 'int main(void){return 0;}\n' | cc -x c - -o /tmp/hello && /tmp/hello && rm /tmp/hello; \
    pkg-config --exists openssl; \
    python3 -c "import yaml, venv"; \
    ldconfig -p | grep -q 'libatomic\.so\.1'; \
    man -w 8 mkfs.ntfs >/dev/null; \
    if grep -rs 'packages\.microsoft\.com' /etc/apt/sources.list /etc/apt/sources.list.d; then \
      echo "packages.microsoft.com is still an apt source" >&2; exit 1; \
    fi; \
    test -x /home/runner/run.sh

# The base image's CMD is /bin/bash; the pod spec sets no command, so the runner starts from here.
CMD ["/home/runner/run.sh"]

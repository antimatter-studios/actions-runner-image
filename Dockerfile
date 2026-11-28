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
# udev: fs-linux-test-harness's ci-setup-linux.sh runs `sudo udevadm` before it boots a KVM guest.
# kmod, fdisk and acl are, like udev, in GitHub's ubuntu-24.04 image, and our jobs and tests call
# them: `sudo modprobe` (rust-fs-fat, rust-fs-core), sfdisk (rust-fs-core's partition oracle),
# setfacl (rust-fs-btrfs's ACL oracle).
# ruby and lsof: fs-linux-test-harness boots its VM through scripts/qemu-artifacts.rb, which needs
# both (`ruby: command not found` failed its smoke jobs here, run 46160731557). ruby-full is what
# GitHub's image installs (Ruby 3.2 with headers, so gems with native extensions build); bundler,
# zlib1g-dev and libyaml-dev come with it there too. The rest are also in GitHub's ubuntu-24.04
# image (images/ubuntu/toolsets/toolset-2404.json) and are what CI scripts call without installing:
# python-is-python3 (`python`, rust-fs-ntfs), netcat-openbsd (`nc`, go-smb2), iproute2, iputils-ping,
# dnsutils, sqlite3, tree, bc, time, psmisc (fuser, pstree), gettext-base (envsubst), the autotools
# and bison/flex/m4 for C dependencies built from source, lz4, pigz and p7zip-full, parallel,
# fakeroot and pipx.
# yq is mikefarah's Go binary, as in GitHub's image (Ubuntu's yq package is a different tool with a
# different syntax); fs-windows-test-harness's ci-ok job calls it. It is pinned by SHA-256.
# packages.microsoft.com is only for installing powershell here, so its package is purged after,
# which removes the apt source: on 2026-11-27 it answered 403 intermittently, and that failed
# `apt-get update` in jobs that installed nothing from it. A job that wants it adds it itself.
# gh comes from GitHub's own apt repository (cli/cli docs/install_linux.md); release jobs call it.
# The keyring checksum is the one those docs publish, so a changed key fails this build. The
# source and key are removed after the install, for the same reason as Microsoft's.
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
      udev kmod fdisk acl \
      ruby-full ruby-bundler zlib1g-dev libyaml-dev lsof \
      python-is-python3 pipx netcat-openbsd iproute2 iputils-ping dnsutils \
      sqlite3 tree bc time psmisc gettext-base \
      autoconf automake libtool bison flex m4 \
      lz4 pigz p7zip-full parallel fakeroot \
 && wget -q -O /tmp/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
 && dpkg -i /tmp/packages-microsoft-prod.deb \
 && rm /tmp/packages-microsoft-prod.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends powershell \
 && dpkg --purge packages-microsoft-prod \
 && wget -q -O /tmp/githubcli.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
 && echo "6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b  /tmp/githubcli.gpg" | sha256sum -c - \
 && install -D -m 0644 /tmp/githubcli.gpg /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm /tmp/githubcli.gpg /etc/apt/sources.list.d/github-cli.list /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && rm -rf /var/lib/apt/lists/* \
 && wget -q -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.54.3/yq_linux_amd64 \
 && echo "129534601871538efe0ba4c5e62a34fb1d5f469bcb975c4fddeb467d82974973  /usr/local/bin/yq" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/yq \
 && mkdir -p /home/runner/.local/bin \
 && chown -R runner:runner /home/runner/.local

ENV PATH=/home/runner/.local/bin:$PATH
USER runner

# Fail the build, not a CI job, if a tool is missing.
RUN set -e; export PATH="$PATH:/usr/sbin:/sbin"; \
    for t in cc c++ make cmake clang ld.lld gdb pkg-config python3 pwsh ntfsfix ntfsls ntfscat shellcheck gh \
             udevadm modprobe lsmod sfdisk fdisk setfacl getfacl \
             ruby gem bundle lsof python pipx nc ip ping dig sqlite3 tree bc /usr/bin/time fuser pstree envsubst \
             autoconf automake libtoolize bison flex m4 lz4 pigz 7z parallel fakeroot yq \
             jq git git-lfs curl wget gpg unzip zip rsync file less gzip xz zstd cpio man; do \
      command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; \
    done; \
    printf 'int main(void){return 0;}\n' | cc -x c - -o /tmp/hello && /tmp/hello && rm /tmp/hello; \
    pkg-config --exists openssl; \
    python3 -c "import yaml, venv"; \
    ldconfig -p | grep -q 'libatomic\.so\.1'; \
    man -w 8 mkfs.ntfs >/dev/null; \
    gh --version; \
    udevadm --version; \
    ruby -e 'require "open3"; require "fileutils"; require "zlib"; require "psych"; require "openssl"; puts RUBY_DESCRIPTION'; \
    ruby -rmkmf -e 'exit(File.exist?(File.join(RbConfig::CONFIG["rubyhdrdir"], "ruby.h")) ? 0 : 1)'; \
    bundle --version; \
    python --version; \
    yq --version | grep -q 'v4\.54\.3'; \
    echo 'a: 1' | yq -r '.a' | grep -qx 1; \
    if grep -rsE 'packages\.microsoft\.com|cli\.github\.com' /etc/apt/sources.list /etc/apt/sources.list.d; then \
      echo "a build-only repository is still an apt source" >&2; exit 1; \
    fi; \
    test -x /home/runner/run.sh

# The base image's CMD is /bin/bash; the pod spec sets no command, so the runner starts from here.
CMD ["/home/runner/run.sh"]

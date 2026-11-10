#!/usr/bin/env bash
# install-user-tools.sh TOOL...
#
# Puts the tools a CI job needs on PATH without root, so one workflow runs on
# GitHub's hosted runners and on the antimatter-vps ARC runners, whose pods
# cannot sudo (allowPrivilegeEscalation: false). A tool already on PATH is left
# alone: hosted runners, which preinstall most of these, skip straight past.
#
# Tools:
#   chore    the release binary, version CHORE_VERSION (required)
#   pwsh     PowerShell's release tarball
#   ntfs-3g  Ubuntu's packages, resolved by apt and unpacked with dpkg-deb
#   cc       conda-forge's GCC, which carries its own sysroot
#
# Everything lands under $HOME/.local. Later steps get PATH and LD_LIBRARY_PATH
# through $GITHUB_PATH and $GITHUB_ENV when they are set.
set -euo pipefail

PWSH_VERSION=7.6.9
MICROMAMBA_VERSION=2.10.0-0
CONDA_GCC_VERSION=14

prefix="$HOME/.local"
bin="$prefix/bin"
mkdir -p "$bin"

case "$(uname -m)" in
    x86_64)        arch=x64;   conda_arch=64;      conda_triple=x86_64-conda-linux-gnu;  conda_target=linux-64 ;;
    aarch64|arm64) arch=arm64; conda_arch=aarch64; conda_triple=aarch64-conda-linux-gnu; conda_target=linux-aarch64 ;;
    *) echo "install-user-tools: unsupported machine $(uname -m)" >&2; exit 1 ;;
esac

add_path() {
    export PATH="$1:$PATH"
    if [ -n "${GITHUB_PATH:-}" ]; then echo "$1" >> "$GITHUB_PATH"; fi
}

add_library_path() {
    export LD_LIBRARY_PATH="$1${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [ -n "${GITHUB_ENV:-}" ]; then echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH" >> "$GITHUB_ENV"; fi
}

have() { PATH="$PATH:/usr/sbin:/sbin" command -v "$1" >/dev/null 2>&1; }

fetch() { curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 "$1"; }

add_path "$bin"

install_chore() {
    have chore && return
    : "${CHORE_VERSION:?install-user-tools: set CHORE_VERSION to install chore}"
    local os
    case "$(uname -s)" in
        Linux)  os=linux ;;
        Darwin) os=darwin ;;
        *) echo "install-user-tools: chore has no build for $(uname -s)" >&2; exit 1 ;;
    esac
    local asset_arch=$arch
    if [ "$os" = linux ] && [ "$arch" = x64 ]; then asset_arch=x86_64; fi
    if [ "$os" = darwin ] && [ "$arch" = x64 ]; then asset_arch=x86_64; fi
    fetch "https://github.com/antimatter-studios/chore/releases/download/v$CHORE_VERSION/chore-$CHORE_VERSION-$os-$asset_arch.tar.gz" \
        | tar xz -C "$bin" chore
}

install_pwsh() {
    have pwsh && return
    local dir="$prefix/opt/powershell-$PWSH_VERSION"
    mkdir -p "$dir"
    fetch "https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VERSION/powershell-$PWSH_VERSION-linux-$arch.tar.gz" \
        | tar xz -C "$dir"
    chmod +x "$dir/pwsh"
    ln -sf "$dir/pwsh" "$bin/pwsh"
}

# apt resolves and downloads as any user once it has its own lists and archive
# directories; dpkg-deb unpacks without touching dpkg's database. Only packages
# apt says are missing are unpacked, so nothing installed is shadowed.
user_apt() {
    local root="$prefix/apt"
    local tree="$root/tree"
    mkdir -p "$root/lists/partial" "$root/archives/partial" "$tree"
    local opts=(
        -q=2
        -o "Dir::State::Lists=$root/lists"
        -o "Dir::Cache::Archives=$root/archives"
        -o "Dir::Cache::pkgcache="
        -o "Dir::Cache::srcpkgcache="
        -o "Debug::NoLocking=1"
        -o "APT::Sandbox::User=$(id -un)"
    )
    apt-get "${opts[@]}" update
    local pkgs
    mapfile -t pkgs < <(apt-get "${opts[@]}" -s install --no-install-recommends "$@" | awk '$1 == "Inst" { print $2 }')
    if [ "${#pkgs[@]}" -eq 0 ]; then return; fi
    (cd "$root/archives" && apt-get "${opts[@]}" download "${pkgs[@]}")
    local deb
    for deb in "$root"/archives/*.deb; do dpkg-deb -x "$deb" "$tree"; done
    local dir
    for dir in usr/bin usr/sbin bin sbin; do
        if [ -d "$tree/$dir" ]; then add_path "$tree/$dir"; fi
    done
    local multiarch
    multiarch="$(uname -m)-linux-gnu"
    for dir in "usr/lib/$multiarch" "lib/$multiarch" usr/lib lib; do
        if [ -d "$tree/$dir" ]; then add_library_path "$tree/$dir"; fi
    done
}

install_ntfs_3g() {
    have ntfsfix && have ntfsls && have ntfscat && return
    user_apt ntfs-3g
}

# GCC unpacked from Ubuntu's packages cannot link: glibc's linker scripts name
# absolute /usr/lib paths that only libc6-dev provides. conda-forge's GCC is
# built to be relocated and brings the glibc sysroot it links against.
install_cc() {
    have cc && return
    local mamba="$prefix/opt/micromamba-$MICROMAMBA_VERSION"
    mkdir -p "$mamba"
    if [ ! -x "$mamba/micromamba" ]; then
        fetch "https://github.com/mamba-org/micromamba-releases/releases/download/$MICROMAMBA_VERSION/micromamba-linux-$conda_arch" \
            > "$mamba/micromamba"
        chmod +x "$mamba/micromamba"
    fi
    local env="$prefix/opt/conda-gcc"
    MAMBA_ROOT_PREFIX="$mamba/root" "$mamba/micromamba" create --yes --quiet \
        --prefix "$env" --channel conda-forge --platform "$conda_target" \
        "gcc_$conda_target=$CONDA_GCC_VERSION" >/dev/null
    local tool
    for tool in cc gcc; do
        ln -sf "$env/bin/$conda_triple-gcc" "$bin/$tool"
    done
    for tool in ar ld nm objcopy ranlib strip; do
        if [ -x "$env/bin/$conda_triple-$tool" ]; then ln -sf "$env/bin/$conda_triple-$tool" "$bin/$tool"; fi
    done
}

for tool in "$@"; do
    case "$tool" in
        chore)   install_chore ;;
        pwsh)    install_pwsh ;;
        ntfs-3g) install_ntfs_3g ;;
        cc)      install_cc ;;
        *) echo "install-user-tools: unknown tool '$tool'" >&2; exit 1 ;;
    esac
done

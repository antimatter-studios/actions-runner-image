#!/usr/bin/env bash
# Runs inside the stock runner image as `runner`, no-new-privileges: the ARC pod's conditions.
set -euo pipefail
export GITHUB_PATH=$HOME/github_path GITHUB_ENV=$HOME/github_env
: > "$GITHUB_PATH"; : > "$GITHUB_ENV"
echo "== whoami: $(id -un), sudo:"; sudo -n true 2>&1 | head -1 || true
echo "== before"; for t in cc pwsh ntfsfix chore python3; do printf '%s: %s\n' "$t" "$(command -v $t || echo missing)"; done
time CHORE_VERSION=0.11.0 bash /work/install-user-tools.sh chore pwsh ntfs-3g cc
# What a later step would see.
while read -r p; do PATH="$p:$PATH"; done < "$GITHUB_PATH"; set -a; . "$GITHUB_ENV"; set +a
echo "== after"
chore --version
pwsh -NoProfile -Command '"pwsh " + $PSVersionTable.PSVersion'
ntfsfix --help 2>&1 | head -1; ntfsls --version 2>&1 | head -1; ntfscat --version 2>&1 | head -1
cc --version | head -1
echo "== rust link test"
curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.95.0 >/dev/null 2>&1
. "$HOME/.cargo/env"
cargo new -q --lib /tmp/t && cd /tmp/t
printf '#[test]\nfn adds() { assert_eq!(2 + 2, 4); }\n' >> src/lib.rs
cargo test -q --release 2>&1 | tail -3
cargo new -q /tmp/b && cd /tmp/b && cargo run -q --release
echo "== mkntfs + ntfsls round trip"
truncate -s 16M /tmp/v.img && mkntfs -q -F -f /tmp/v.img && ntfsls /tmp/v.img | head -3
echo ALL-OK

#!/usr/bin/env bash
# Runs inside the stock runner image as `runner`, no-new-privileges: the ARC pod's conditions.
set -euo pipefail
export GITHUB_PATH=$HOME/github_path GITHUB_ENV=$HOME/github_env
: > "$GITHUB_PATH"; : > "$GITHUB_ENV"
echo "== $(id -un); sudo: $(sudo -n true 2>&1 | head -1)"
echo "== first run (cold)"
time bash /work/install-user-tools.sh chore pwsh ntfs-3g cc
du -sh ~/.local/user-tools
while read -r p; do PATH="$p:$PATH"; done < "$GITHUB_PATH"; set -a; . "$GITHUB_ENV"; set +a
chore --version | head -1
pwsh -NoProfile -Command '"pwsh " + $PSVersionTable.PSVersion'
for t in ntfsfix ntfsls ntfscat mkntfs; do printf '%s -> %s\n' "$t" "$(command -v $t)"; done
cc --version | head -1
echo "== rust link with zig cc"
curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain 1.95.0 >/dev/null 2>&1
. "$HOME/.cargo/env"
cargo new -q --lib /tmp/t && cd /tmp/t
printf '#[test]\nfn adds() { assert_eq!(2 + 2, 4); }\n' >> src/lib.rs
time cargo test -q --release 2>&1 | tail -3
cargo new -q /tmp/b && cd /tmp/b && cargo run -q --release
echo "== ntfs round trip"
truncate -s 16M /tmp/v.img && mkntfs -q -F -f /tmp/v.img && ntfsls /tmp/v.img | head -3
echo "== second run over the same directory (what a cache hit looks like)"
: > "$GITHUB_PATH"; : > "$GITHUB_ENV"
env -i HOME=$HOME PATH=/usr/local/bin:/usr/bin:/bin GITHUB_PATH=$GITHUB_PATH GITHUB_ENV=$GITHUB_ENV bash -c 'time bash /work/install-user-tools.sh chore pwsh ntfs-3g cc'
cat "$GITHUB_PATH"
echo ALL-OK

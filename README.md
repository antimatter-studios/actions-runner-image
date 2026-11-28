# actions-runner-image

`ghcr.io/antimatter-studios/actions-runner`: the image the ARC runner scale sets on the
antimatter-vps cluster run. It is `ghcr.io/actions/actions-runner` plus the OS tools GitHub's
`ubuntu-24.04` image preinstalls and our workflows expect (build-essential, clang, cmake, Python
with PyYAML, PowerShell, GitHub CLI, ntfs-3g, udev, kmod, man pages). Everything is installed at build time: a runner
pod runs `run.sh` and nothing else, so it never waits on an apt mirror. Add a tool a job needs
here, not to a workflow's `sudo apt-get` or to the pod's startup.

`packages.microsoft.com` (for PowerShell) and `cli.github.com/packages` (for `gh`) are apt sources
only while the image is built. Jobs do not have them, so their outages cannot fail their
`apt-get update`. The `gh` repository's keyring is pinned by SHA-256.

Language toolchains (Go, Node, Rust, Helm) do not belong here: workflows use `setup-*` actions.

The base image is pinned by tag and digest, and Dependabot bumps it. A pull request builds the
image and runs its checks; every push to `main` publishes `<runner version>-<short sha>` and prints
the reference with its digest in the run summary. antimatter-vps pins that reference, digest
included, in `src/githubActionsRunners.ts`.

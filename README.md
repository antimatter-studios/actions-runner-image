# actions-runner-image

`ghcr.io/antimatter-studios/actions-runner`: the image the ARC runner scale sets on the
antimatter-vps cluster run. It is `ghcr.io/actions/actions-runner` plus the OS tools GitHub's
`ubuntu-24.04` image preinstalls and our workflows expect (build-essential, clang, cmake, the
autotools, Python with PyYAML and pipx, Ruby with bundler, PowerShell, GitHub CLI, jq, yq, ntfs-3g,
udev, kmod, lsof, network and compression tools, man pages). Everything is installed at build
time: a runner pod runs `run.sh` and nothing else, so it never waits on an apt mirror. Add a tool a
job needs here, not to a workflow's `sudo apt-get` or to the pod's startup, and add it to the
build's final check so the build fails if it is missing.

What GitHub's image has and this one does not, on purpose: Node.js, Java, .NET, Android, Swift,
Julia, Kotlin, browsers and Xvfb, Homebrew, Miniconda, vcpkg, the cloud CLIs (AWS, Azure, Google
Cloud), kubectl, Helm, Pulumi and Docker Compose. Workflows that need one install it, mostly
through a `setup-*` action.

`packages.microsoft.com` (for PowerShell) and `cli.github.com/packages` (for `gh`) are apt sources
only while the image is built. Jobs do not have them, so their outages cannot fail their
`apt-get update`. The `gh` repository's keyring is pinned by SHA-256.

Version-pinned language toolchains (Go, Node, Rust, Helm) do not belong here: workflows use
`setup-*` actions. Ruby and Python are the distribution's, as on GitHub's image, for scripts.

The base image is pinned by tag and digest, and Dependabot bumps it. A pull request builds the
image and runs its checks; every push to `main` publishes `<runner version>-<short sha>` and prints
the reference with its digest in the run summary. antimatter-vps pins that reference, digest
included, in `src/githubActionsRunners.ts`.

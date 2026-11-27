# actions-runner-image

`ghcr.io/antimatter-studios/actions-runner`: the image the ARC runner scale sets on the
antimatter-vps cluster run. It is `ghcr.io/actions/actions-runner` plus the OS tools GitHub's
`ubuntu-24.04` image preinstalls and our workflows expect (build-essential, clang, cmake, Python
with PyYAML, PowerShell, ntfs-3g, man pages). Everything is installed at build time: a runner
pod runs `run.sh` and nothing else, so it never waits on an apt mirror. Add a tool a job needs
here, not to a workflow's `sudo apt-get` or to the pod's startup.

`packages.microsoft.com` is an apt source only while the image is built (for PowerShell). Jobs do
not have it, so its outages cannot fail their `apt-get update`.

Language toolchains (Go, Node, Rust, Helm) do not belong here: workflows use `setup-*` actions.

The base image is pinned by tag and digest. A pull request builds the image and runs its checks;
every push to `main` publishes `<runner version>-<short sha>` and prints the reference with its
digest in the run summary. antimatter-vps pins that reference, digest included, in
`src/githubActionsRunners.ts`.

## Runner updates

GitHub stops sending jobs to a self-hosted runner some weeks after a newer actions/runner release.
`runner-update.yaml` runs daily: when a release is newer than the `FROM` line, it pushes
`runner-update/<version>`, starts the build on that branch (a build off `main` publishes nothing)
and opens a PR. Dependabot also bumps the base image, weekly.

It uses only `GITHUB_TOKEN`. Opening the PR needs *Allow GitHub Actions to create and approve pull
requests* in the organization and repository Actions settings; without it the run fails after
pushing the branch.

# actions-runner-image

`ghcr.io/antimatter-studios/actions-runner`: the image the ARC runner scale sets on the
antimatter-vps cluster run. It is `ghcr.io/actions/actions-runner` plus the tools our
workflows expect from GitHub's `ubuntu-latest` (build-essential, Python, PowerShell,
ntfs-3g). Runner pods run without privilege escalation, so jobs cannot `sudo apt-get`;
add a tool here instead.

Every push to `main` publishes `<runner version>-<short sha>` and `latest`. The cluster
pins the first one in antimatter-vps (`src/githubActionsRunners.ts`).

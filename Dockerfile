# The actions-runner image ARC starts, plus the tools that GitHub's ubuntu-latest
# preinstalls and our workflows expect. Runner pods cannot use sudo
# (allowPrivilegeEscalation: false), so anything a job needs from apt is here.
ARG RUNNER_VERSION=2.338.2
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config ca-certificates wget \
      python3 python3-venv file gzip xz-utils zstd \
      ntfs-3g shellcheck \
 && wget -q -O /tmp/packages-microsoft-prod.deb https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb \
 && dpkg -i /tmp/packages-microsoft-prod.deb \
 && rm /tmp/packages-microsoft-prod.deb \
 && apt-get update \
 && apt-get install -y --no-install-recommends powershell \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /home/runner/.local/bin \
 && chown -R runner:runner /home/runner/.local

ENV PATH=/home/runner/.local/bin:$PATH
USER runner

# Fail the build, not a CI job, if a tool is missing.
RUN export PATH="$PATH:/usr/sbin:/sbin"; \
    for t in cc make pkg-config pwsh python3 ntfsfix ntfsls ntfscat jq git curl unzip gzip xz zstd file; do \
      command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; \
    done

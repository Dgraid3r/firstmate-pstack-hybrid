# Local CI image: the Linux toolchain the lint and portable behavior lanes need,
# with the same pinned ShellCheck and actionlint that GitHub CI installs.
# Used through docker-compose.ci.yml (docs/local-ci.md).
# Herdr and macOS lanes are not part of this image; they stay manual on GitHub.
FROM node:22-bookworm-slim AS node

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates coreutils curl file git jq lsof procps psmisc \
      python3 ruby tar time tmux util-linux xz-utils \
 && rm -rf /var/lib/apt/lists/*
# GitHub runners ship Chrome, and fm-calm-pi-extension.test.sh needs one for its
# rendered-export assertions. Google publishes no arm64 Linux build, so on arm64
# that one test fails here and the rest are unaffected.
RUN if [ "$(dpkg --print-architecture)" = amd64 ]; then \
      curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
      && apt-get update && apt-get install -y --no-install-recommends /tmp/chrome.deb \
      && rm -rf /tmp/chrome.deb /var/lib/apt/lists/*; \
    fi
# GitHub runners default to a UTF-8 locale; the Cortex harness test measures
# box-drawing rows in characters and fails under the POSIX locale.
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
COPY --from=node /usr/local/ /usr/local/

# The installers read the pinned versions from bin/fm-lint.sh, so only these
# scripts enter the image and the layer rebuilds only when they change.
WORKDIR /opt/fm-tools
COPY bin/fm-lint.sh bin/fm-lint-workflows.sh bin/fm-install-shellcheck.sh bin/fm-install-actionlint.sh ./bin/
RUN mkdir -p /opt/fm-tools/pinned \
 && bin/fm-install-shellcheck.sh /opt/fm-tools/pinned \
 && bin/fm-install-actionlint.sh /opt/fm-tools/pinned
# Same npm packages the CI lanes install so the Pi and backlog-handoff tests
# exercise their real surfaces instead of capability-skipping.
RUN npm install -g tasks-axi @earendil-works/pi-coding-agent \
 && npm cache clean --force
ENV PATH=/opt/fm-tools/pinned:$PATH

COPY docker/ci/entrypoint.sh /usr/local/bin/fm-ci-entrypoint
RUN chmod +x /usr/local/bin/fm-ci-entrypoint \
 && mkdir /work && chown ubuntu:ubuntu /work
USER ubuntu
ENV HOME=/home/ubuntu
ENTRYPOINT ["/usr/local/bin/fm-ci-entrypoint"]

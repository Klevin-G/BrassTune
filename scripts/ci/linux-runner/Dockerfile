FROM ubuntu@sha256:7f622ca8766bccb22f04242ecb6f19f770b2f08827dc4b8c707de5e78a6da7ab

ARG RUNNER_VERSION=2.336.0
ARG RUNNER_SHA256=58b758e420b87093fbd4bfddd368074960053e2f1388f01848c82624b90f27d1

ENV DEBIAN_FRONTEND=noninteractive

# Runtime dependencies are installed while building the trusted image. Workflow
# code must not mutate the host or elevate through sudo at job runtime.
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        libsqlite3-0 \
        nodejs \
        npm \
        postgresql \
        postgresql-client \
        unzip \
        xz-utils \
        zip \
    && npx --yes playwright@1.61.0 install-deps chromium firefox webkit \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 1001 runner \
    && useradd --uid 1001 --gid 1001 --create-home --shell /bin/bash runner

WORKDIR /opt/actions-runner-template

RUN curl --fail --location --retry 3 \
        --output /tmp/actions-runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz" \
    && printf '%s  %s\n' "${RUNNER_SHA256}" /tmp/actions-runner.tar.gz | sha256sum --check --strict - \
    && tar --extract --gzip --file /tmp/actions-runner.tar.gz --directory /opt/actions-runner-template \
    && ./bin/installdependencies.sh \
    && rm -f /tmp/actions-runner.tar.gz

COPY entrypoint.sh /usr/local/bin/brasstune-runner-entrypoint

RUN chmod 0755 /usr/local/bin/brasstune-runner-entrypoint \
    && mkdir -p /opt/actions-runner \
    && chown -R runner:runner /opt/actions-runner-template /opt/actions-runner

USER runner
WORKDIR /opt/actions-runner

ENTRYPOINT ["/usr/local/bin/brasstune-runner-entrypoint"]

FROM swift:6.0-noble AS builder
WORKDIR /boka

RUN apt-get update && \
	apt-get dist-upgrade -y -o Dpkg::Options::="--force-confold" && \
	apt-get install -y curl build-essential cmake librocksdb-dev libzstd-dev libbz2-dev liblz4-dev

# install rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

COPY . .

RUN make deps

WORKDIR /boka/Boka

RUN swift build

RUN cp $(swift build --show-bin-path)/Boka /boka/boka-bin

WORKDIR /boka

# RUN ./boka-bin --help

# =============

FROM phusion/baseimage:noble-1.0.0
LABEL maintainer="hello@laminar.one"

# from https://github.com/swiftlang/swift-docker/blob/38e4244ebab3d6a4e702fb30449827d6c28ee1fd/6.0/ubuntu/24.04/slim/Dockerfile
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && apt-get -q update && \
    apt-get -q install -y \
    libcurl4 \
    libxml2 \
    tzdata \
    && rm -r /var/lib/apt/lists/*

# Everything up to here should cache nicely between Swift versions, assuming dev dependencies change little

# pub   rsa4096 2024-09-16 [SC] [expires: 2026-09-16]
#      52BB7E3DE28A71BE22EC05FFEF80A866B47A981F
# uid           [ unknown] Swift 6.x Release Signing Key <swift-infrastructure@forums.swift.org>
ARG SWIFT_SIGNING_KEY=52BB7E3DE28A71BE22EC05FFEF80A866B47A981F
ARG SWIFT_PLATFORM=ubuntu24.04
ARG SWIFT_BRANCH=swift-6.0.1-release
ARG SWIFT_VERSION=swift-6.0.1-RELEASE
ARG SWIFT_WEBROOT=https://download.swift.org

ENV SWIFT_SIGNING_KEY=$SWIFT_SIGNING_KEY \
    SWIFT_PLATFORM=$SWIFT_PLATFORM \
    SWIFT_BRANCH=$SWIFT_BRANCH \
    SWIFT_VERSION=$SWIFT_VERSION \
    SWIFT_WEBROOT=$SWIFT_WEBROOT

RUN set -e; \
    ARCH_NAME="$(dpkg --print-architecture)"; \
    url=; \
    case "${ARCH_NAME##*-}" in \
        'amd64') \
            OS_ARCH_SUFFIX=''; \
            ;; \
        'arm64') \
            OS_ARCH_SUFFIX='-aarch64'; \
            ;; \
        *) echo >&2 "error: unsupported architecture: '$ARCH_NAME'"; exit 1 ;; \
    esac; \
    SWIFT_WEBDIR="$SWIFT_WEBROOT/$SWIFT_BRANCH/$(echo $SWIFT_PLATFORM | tr -d .)$OS_ARCH_SUFFIX" \
    && SWIFT_BIN_URL="$SWIFT_WEBDIR/$SWIFT_VERSION/$SWIFT_VERSION-$SWIFT_PLATFORM$OS_ARCH_SUFFIX.tar.gz" \
    && SWIFT_SIG_URL="$SWIFT_BIN_URL.sig" \
    # - Grab curl and gpg here so we cache better up above
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -q update && apt-get -q install -y curl gnupg && rm -rf /var/lib/apt/lists/* \
    # - Download the GPG keys, Swift toolchain, and toolchain signature, and verify.
    && export GNUPGHOME="$(mktemp -d)" \
    && curl -fsSL "$SWIFT_BIN_URL" -o swift.tar.gz "$SWIFT_SIG_URL" -o swift.tar.gz.sig \
    && gpg --batch --quiet --keyserver keyserver.ubuntu.com --recv-keys "$SWIFT_SIGNING_KEY" \
    && gpg --batch --verify swift.tar.gz.sig swift.tar.gz \
    # - Unpack the toolchain, set libs permissions, and clean up.
    && tar -xzf swift.tar.gz --directory / --strip-components=1 \
        $SWIFT_VERSION-$SWIFT_PLATFORM$OS_ARCH_SUFFIX/usr/lib/swift/linux \
        $SWIFT_VERSION-$SWIFT_PLATFORM$OS_ARCH_SUFFIX/usr/libexec/swift/linux \
    && chmod -R o+r /usr/lib/swift /usr/libexec/swift \
    && rm -rf "$GNUPGHOME" swift.tar.gz.sig swift.tar.gz \
    && apt-get purge --auto-remove -y curl gnupg

RUN useradd -m -u 1001 -U -s /bin/sh -d /boka boka

COPY --from=builder /boka/boka-bin /usr/local/bin/boka

# checks
RUN ldd /usr/local/bin/boka && \
	/usr/local/bin/boka --help

USER boka

EXPOSE 9955

RUN mkdir /boka/data

VOLUME ["/boka/data"]

ENTRYPOINT ["/usr/local/bin/boka"]
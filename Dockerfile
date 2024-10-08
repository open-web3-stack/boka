FROM swift:6.0-noble AS builder
WORKDIR /boka

RUN apt-get update && \
	apt-get dist-upgrade -y -o Dpkg::Options::="--force-confold" && \
	apt-get install -y cmake pkg-config libssl-dev git clang libclang-dev protobuf-compiler

COPY . .

RUN ./scripts/build-external-libs.sh
RUN make deps

WORKDIR /boka/Boka

RUN swift build -c release

RUN cp $(swift build --show-bin-path -c release)/Boka /boka/boka

# =============

FROM phusion/baseimage:noble-1.0.0
LABEL maintainer="hello@laminar.one"

RUN useradd -m -u 1001 -U -s /bin/sh -d /boka boka

COPY --from=builder /boka/boka /usr/local/bin

# checks
RUN ldd /usr/local/bin/boka && \
	/usr/local/bin/boka --help

USER boka

EXPOSE 9955

RUN mkdir /boka/data

VOLUME ["/boka/data"]

ENTRYPOINT ["/usr/local/bin/boka"]

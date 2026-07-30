# ==========================================
# Stage 1: Build Stage (Open5GS v2.8.0)
# ==========================================
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    ninja-build \
    build-essential \
    flex \
    bison \
    git \
    cmake \
    libsctp-dev \
    libgnutls28-dev \
    libgcrypt20-dev \
    libssl-dev \
    libidn11-dev \
    libtalloc-dev \
    libmicrohttpd-dev \
    libmongoc-dev \
    libbson-dev \
    libyaml-dev \
    libnghttp2-dev \
    libcurl4-openssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install meson==1.3.2

WORKDIR /sources
RUN git clone --recursive -b v2.8.0 https://github.com/open5gs/open5gs.git

WORKDIR /sources/open5gs
RUN meson build --prefix=/usr/local && \
    ninja -C build install

# ==========================================
# Stage 2: Production Runtime Stage
# ==========================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsctp1 \
    libgnutls30 \
    libgcrypt20 \
    libssl3 \
    libidn12 \
    libidn2-0 \
    libtalloc2 \
    libmicrohttpd12 \
    libmongoc-1.0-0 \
    libbson-1.0-0 \
    libyaml-0-2 \
    libnghttp2-14 \
    libcurl4 \
    nghttp2-client \
    iproute2 \
    iptables \
    net-tools \
    iputils-ping \
    curl \
    tcpdump \
    tshark \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/open5gs-* /usr/local/bin/
COPY --from=builder /usr/local/lib/ /usr/local/lib/
COPY --from=builder /usr/local/etc/open5gs/ /usr/local/etc/open5gs/

RUN mkdir -p /usr/local/var/log/open5gs /usr/local/var/run && ldconfig

WORKDIR /usr/local/etc/open5gs

CMD ["open5gs-nrfd"]
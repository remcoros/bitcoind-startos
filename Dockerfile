# From https://github.com/ruimarinho/docker-bitcoin-core

# Build stage for BerkeleyDB
FROM lncm/berkeleydb as berkeleydb

# Build stage for Bitcoin Core
FROM alpine:3.20 as bitcoin-core

COPY --from=berkeleydb /opt /opt

RUN sed -i 's/http\:\/\/dl-cdn.alpinelinux.org/https\:\/\/alpine.global.ssl.fastly.net/g' /etc/apk/repositories
RUN apk --no-cache add \
        autoconf \
        automake \
        boost-dev \
        build-base \
        clang \
        chrpath \
        file \
        gnupg \
        libevent-dev \
        libressl \
        libtool \
        linux-headers \
        sqlite-dev \
        zeromq-dev

ADD ./bitcoin /bitcoin

ENV BITCOIN_PREFIX=/opt/bitcoin

WORKDIR /bitcoin

RUN ./autogen.sh
RUN ./configure LDFLAGS=-L`ls -d /opt/db*`/lib/ CPPFLAGS=-I`ls -d /opt/db*`/include/ \
  # If building on Mac make sure to increase Docker VM memory, or uncomment this line. See https://github.com/bitcoin/bitcoin/issues/6658 for more info.
  # CXXFLAGS="--param ggc-min-expand=1 --param ggc-min-heapsize=32768" \
  CXXFLAGS="-g0 -O3" \
  CXX=clang++ CC=clang \
  --prefix=${BITCOIN_PREFIX} \
  --disable-man \
  --disable-tests \
  --disable-bench \
  --disable-ccache \
  --disable-fuzz \
  --disable-fuzz-binary \
  --with-gui=no \
  --with-utils \
  #  --with-libs \
  --with-sqlite=yes \
  --with-daemon

RUN make -j$(nproc)
RUN make install
RUN strip ${BITCOIN_PREFIX}/bin/*
#RUN strip ${BITCOIN_PREFIX}/lib/libbitcoinconsensus.a
#RUN strip ${BITCOIN_PREFIX}/lib/libbitcoinconsensus.so.0.0.0

# Build stage for compiled artifacts
FROM alpine:3.20

LABEL maintainer.0="João Fonseca (@joaopaulofonseca)" \
  maintainer.1="Pedro Branco (@pedrobranco)" \
  maintainer.2="Rui Marinho (@ruimarinho)" \
  maintainer.3="Aiden McClelland (@dr-bonez)"

RUN sed -i 's/http\:\/\/dl-cdn.alpinelinux.org/https\:\/\/alpine.global.ssl.fastly.net/g' /etc/apk/repositories
RUN \
  apk --no-cache add \
  bash \
  curl \
  libevent \
  libzmq \
  sqlite-dev \
  tini \
  yq && \
  rm -rf /var/cache/apk/*

ARG ARCH

ENV BITCOIN_DATA=/root/.bitcoin
ENV BITCOIN_PREFIX=/opt/bitcoin
ENV PATH=${BITCOIN_PREFIX}/bin:$PATH

COPY --from=bitcoin-core /opt /opt
COPY --chmod=755 \
  ./manager/target/${ARCH}-unknown-linux-musl/release/bitcoind-manager \
  ./docker_entrypoint.sh \
  ./actions/reindex.sh \
  ./actions/reindex_chainstate.sh \
  ./check-rpc.sh \
  ./check-synced.sh \
  /usr/local/bin/

EXPOSE 48332 8333

ENTRYPOINT ["/usr/local/bin/docker_entrypoint.sh"]

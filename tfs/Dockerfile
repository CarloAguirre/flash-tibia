FROM debian:bookworm-slim AS build
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    libboost-system-dev \
    libboost-iostreams-dev \
    libboost-filesystem-dev \
    libboost-date-time-dev \
    libcrypto++-dev \
    libfmt-dev \
    libgmp-dev \
    libluajit-5.1-dev \
    libmariadb-dev \
    libmariadb-dev-compat \
    default-libmysqlclient-dev \
    libpugixml-dev \
    pkg-config \
 && rm -rf /var/lib/apt/lists/*

COPY cmake /usr/src/forgottenserver/cmake/
COPY src   /usr/src/forgottenserver/src/
COPY CMakeLists.txt /usr/src/forgottenserver/
WORKDIR /usr/src/forgottenserver/build
RUN cmake -DCMAKE_BUILD_TYPE=Release .. && make -j"$(nproc)"

FROM debian:bookworm-slim
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libboost-system1.74.0 \
    libboost-iostreams1.74.0 \
    libboost-filesystem1.74.0 \
    libboost-date-time1.74.0 \
    libcrypto++8 \
    libfmt9 \
    libgmp10 \
    libluajit-5.1-2 \
    libmariadb3 \
    libpugixml1v5 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/src/forgottenserver/build/tfs /bin/tfs
COPY data /srv/data/
COPY LICENSE README.md *.dist *.sql key.pem /srv/

EXPOSE 7171 7172
WORKDIR /srv
VOLUME /srv
ENTRYPOINT ["/bin/tfs"]

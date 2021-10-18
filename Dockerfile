FROM ubuntu:focal AS ubuntu-base
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends wget ca-certificates

FROM ubuntu-base AS downloader
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends aria2 && mkdir /downloads
COPY downloads.txt /downloads.txt
RUN aria2c -i /downloads.txt -d /downloads

FROM ubuntu-base AS build-essential
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential automake gperf bison flex texinfo gawk libtool libncurses5-dev help2man unzip libtool-bin

FROM build-essential AS build-ct-ng
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libarchive-tools
COPY --from=downloader /downloads/crosstool-ng-2a770f3.zip /crosstool-ng.zip
COPY patches/crosstool-ng /patches
RUN mkdir /crosstool-ng && \
    bsdtar -xf /crosstool-ng.zip --strip-components=1 -C /crosstool-ng && \
    cd /crosstool-ng && \
    for i in /patches/*.patch; do patch -p1 < $i; done && \
    ./bootstrap && \
    ./configure --enable-local && \
    make -j$((`nproc`+1))

FROM build-essential AS build-bootstrap
COPY --from=build-ct-ng /crosstool-ng /crosstool-ng
RUN mkdir /build
COPY --from=downloader /downloads /build/downloads/
COPY defconfig-bootstrap /build/defconfig
COPY patches /build/patches/

# build the bootstrap toolchain, but remove the intermediate files
# they can't really be cached, but make docker think, which is ~~bad for it's health~~ slow
# 11.2GiB is also a lot to cache... So it's ditched
RUN cd /build && \
    /crosstool-ng/ct-ng defconfig && \
    CT_ALLOW_BUILD_AS_ROOT_SURE=LOL /crosstool-ng/ct-ng build && \
    /toolchain-bootstrap/bin/x86_64-linux-gnu-gcc --version && \
    rm -rf /build/build

# build the final toolchain which itself depends on some old version of glibc
FROM build-essential AS build-real
# force uninstall gcc to make sure we don't use it inadvertently
RUN dpkg -r --force-depends cpp gcc g++ cpp-9 gcc-9 g++-9 gcc-9-base libgcc-9-dev libasan5 libc6-dev libstdc++-9-dev
COPY --from=build-ct-ng /crosstool-ng /crosstool-ng
COPY --from=build-bootstrap /toolchain-bootstrap /toolchain-bootstrap
RUN mkdir /build
COPY --from=downloader /downloads /build/downloads/
COPY defconfig-real /build/defconfig
COPY patches /build/patches/
RUN cd /build && \
    /crosstool-ng/ct-ng defconfig && \
    PATH="/toolchain-bootstrap/bin:$PATH" CT_ALLOW_BUILD_AS_ROOT_SURE=LOL /crosstool-ng/ct-ng build && \
    /toolchain-real/bin/x86_64-linux-gnu-gcc --version && \
    rm -rf /build/build

FROM scratch
COPY --from=build-real /toolchain-real /toolchain-real/


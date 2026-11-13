# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

FROM quay.io/fedora/fedora:44 AS tamamo-build
ARG ZIG_VERSION=0.17.1
ARG ZIG_SHA256=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a
COPY tamamo /src
RUN set -eu; \
    command -v xz >/dev/null || dnf -y install xz; \
    f="zig-x86_64-linux-${ZIG_VERSION}.tar.xz"; \
    for m in $(curl -fsSL https://ziglang.org/download/community-mirrors.txt | shuf) "https://ziglang.org/download/${ZIG_VERSION}"; do \
        if curl -fsSL --max-time 300 -o "/tmp/$f" "$m/$f?source=tamamo" && echo "${ZIG_SHA256}  /tmp/$f" | sha256sum -c -; then break; fi; \
        rm -f "/tmp/$f"; \
    done; \
    test -f "/tmp/$f"; \
    mkdir /opt/zig; \
    tar -xJf "/tmp/$f" -C /opt/zig --strip-components=1; \
    cd /src; \
    /opt/zig/zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux --prefix /out

# Base Image
FROM ghcr.io/ublue-os/silverblue-main:44
## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:testing
# FROM ghcr.io/ublue-os/aurora:stable
# FROM ghcr.io/ublue-os/bluefin-nvidia-open:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:44
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

# RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

COPY --from=tamamo-build /out/bin/tamamo /usr/bin/tamamo

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint

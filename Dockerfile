# Dockerfile
#
# Pinned deliberately. This was "ubuntu:latest", which silently rolled to 26.04
# and broke the build: qemu-user-static no longer exists there (it was split
# into qemu-user-binfmt). A build host that changes under you is exactly what
# you do not want when the output is a bootable disk image.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
    vim fdisk ssh python3 e2fsprogs software-properties-common proot lsof gdisk bsdmainutils file \
    mount parted kpartx util-linux wget curl gnupg2 xz-utils zstd qemu-user-static \
    debootstrap systemd-container openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]


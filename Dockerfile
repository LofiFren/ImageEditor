# Dockerfile
FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
    vim fdisk ssh python3 e2fsprogs software-properties-common proot lsof gdisk bsdmainutils file \
    mount parted kpartx util-linux wget curl gnupg2 xz-utils qemu-user-static \
    debootstrap systemd-container && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]


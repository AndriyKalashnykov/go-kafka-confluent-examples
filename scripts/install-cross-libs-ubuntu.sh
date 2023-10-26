#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
if [[ "${TRACE-0}" == "1" ]]; then
    set -o xtrace
fi

sudo apt install software-properties-common -y
#sudo add-apt-repository ppa:deadsnakes/ppa
#sudo apt-get install -y Python3.10
sudo apt install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev

sudo apt-get install -y cmake git patch gettext unzip musl-tools lzma-dev libssl-dev libxml2-dev libghc-zlib-dev libexpat1-dev bzip2 cpio

#gcc-x86-64-linux-gnu
sudo apt-get install -y build-essential gcc libmpfr-dev libgmp3-dev libmpc-dev gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu --install-suggests
sudo apt-get install -y gcc-arm-linux-gnueabihf libc6-dev-armhf-cross gcc-aarch64-linux-gnu libc6-dev-arm64-cross --no-install-recommends

## windows
sudo apt-get install -y *-w64-x86-*

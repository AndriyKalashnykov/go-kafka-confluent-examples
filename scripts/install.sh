#!/usr/bin/env bash

set -euo pipefail

VERSION_TO_INSTALL=${1:-}
VERSION_INSTALLED=""

# discover the operating system for this system.
  OS=$(uname -s)
  case $OS in
    mingw*|cygwin*|windows*) OS='windows';;
    Darwin) OS='darwin';;
    FreeBSD) OS='freebsd';;
    *) OS='linux';;
  esac

  ARCH=$(uname -m)
	if [[ $ARCH == 'x86_64' ]]; then
		ARCH='amd64'
	elif [[ $ARCH == 'ppc64le' ]]; then
		ARCH='ppc64le'
	elif [[ $ARCH == 'aarch64' || $ARCH == 'arm64' || $ARCH == 'armv8' ]]; then
		ARCH="arm64"
	elif [[ $ARCH == "i386" || $ARCH == "i686" ]]; then
		ARCH='386'
	elif [[ $ARCH == 'armv7l' || $ARCH == 'armv6l' || $ARCH == 'armv5tel' ]]; then
	  ARCH="arm"
	  case $ARCH in
      'armv5tel')
        ARMV='5';;
      'armv6l')
        ARMV='6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || ARMV='v5';;
      'armv7' | 'armv7l')
        ARMV='7'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || ARMV='v5';;
    esac
	else
		ARCH='s390x'
	fi

  TMP_DIR=/tmp
  LOCAL_DIR=/usr/local
  BIN_DIR=$LOCAL_DIR/bin
  TGZ_EXT=.tgz
  TAR_GZ_EXT=.tar.gz

  USER=AndriyKalashnykov
  PROJECT=go-kafka-confluent-examples

  if [ -z "${VERSION_TO_INSTALL}" ]; then
      VERSION_TO_INSTALL=$(curl -sL https://api.github.com/repos/$USER/$PROJECT/releases/latest  | grep '"tag_name":' | awk -F '"' '{printf("%s",$4)}' | cut -c 2-)
  fi

  if [ -f "$BIN_DIR/$PROJECT" ]; then
      VERSION_INSTALLED=$($BIN_DIR/$PROJECT --version | grep "version" | awk '{printf("%s",$3)}')
  fi

	BINARY_FILE=https://github.com/${USER}/${PROJECT}/releases/download/v${VERSION_TO_INSTALL}/${PROJECT}_v${VERSION_TO_INSTALL}_${OS}_${ARCH}${TAR_GZ_EXT}
	echo $OS
	echo $ARCH
	if [[ $ARCH == 'arm' ]]; then
	  echo $ARMV
	fi
	echo $VERSION_TO_INSTALL
	echo $VERSION_INSTALLED
	echo $BINARY_FILE

exit 0

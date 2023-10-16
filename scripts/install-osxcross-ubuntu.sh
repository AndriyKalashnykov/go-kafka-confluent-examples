#!/usr/bin/env bash

CLANGVERSION=$(clang++ --version 2>&1 | head -1 | awk '{print $4}')
MACOSXSDKVERSION=14.0
MACOSXSDK=MacOSX${MACOSXSDKVERSION}.sdk.tar.xz

ROOTDIR=/opt
OSXCROSSDIR=osxcross-clang-${CLANGVERSION}-macosx-${MACOSXSDKVERSION}
OSXCROSSZIP=osxcross.zip

echo "Create $ROOTDIR/$OSXCROSSDIR and set owner to $USER"
sudo rmdir $ROOTDIR/$OSXCROSSDIR
sudo mkdir -p $ROOTDIR/$OSXCROSSDIR
sudo chown -R $USER $ROOTDIR/$OSXCROSSDIR

if [ -d "$ROOTDIR/$OSXCROSSZIP" ]; then
  sudo rm -f $ROOTDIR/$OSXCROSSZIP
fi

cd $ROOTDIR || exit 1
# sudo git clone https://github.com/tpoechtrager/osxcross.git
# sudo git clone git@github.com:tpoechtrager/osxcross.git
sudo curl -L -o $ROOTDIR/$OSXCROSSZIP https://github.com/tpoechtrager/osxcross/archive/refs/heads/master.zip
sudo chown -R $USER $ROOTDIR/$OSXCROSSZIP
unzip $ROOTDIR/$OSXCROSSZIP -d $ROOTDIR/$OSXCROSSDIR
mv $ROOTDIR/$OSXCROSSDIR/osxcross-master/* $ROOTDIR/$OSXCROSSDIR/
rm -rf $ROOTDIR/$OSXCROSSDIR/osxcross-master
cd $ROOTDIR/$OSXCROSSDIR || exit 1
# https://github.com/joseluisq/macosx-sdks/
curl -L -o ./tarballs/$MACOSXSDK https://github.com/joseluisq/macosx-sdks/releases/download/14.0/$MACOSXSDK
UNATTENDED=1 PORTABLE=true ./build.sh

echo "Don't forget to add to the PATH"
echo 'export PATH=$PATH:$ROOTDIR/$OSXCROSSDIR/target/bin'
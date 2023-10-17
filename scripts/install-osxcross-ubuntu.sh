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
UNATTENDED=1 PORTABLE=true ./build_gcc.sh
UNATTENDED=1 PORTABLE=true ./build_apple_clang.sh*

# repo info
# https://api.github.com/repos/AndriyKalashnykov/osxcross-target

#git lfs install
#git lfs migrate import --include=bin/x86_64-apple-darwin23-lto-dump
#git lfs migrate import --include=libexec/gcc/x86_64-apple-darwin23/13.2.0/cc1
#git lfs migrate import --include=libexec/gcc/x86_64-apple-darwin23/13.2.0/cc1obj
#git lfs migrate import --include=libexeclibexec/gcc/x86_64-apple-darwin23/13.2.0/cc1objplus
#git lfs migrate import --include=libexec/gcc/x86_64-apple-darwin23/13.2.0/cc1objplus
#git lfs migrate import --include=libexec/gcc/x86_64-apple-darwin23/13.2.0/cc1plus
#git lfs migrate import --include=libexec/gcc/x86_64-apple-darwin23/13.2.0/lto1

#git lfs uninstall
#git lfs untrack bin/x86_64-apple-darwin23-lto-dump
#git lfs untrack libexec/gcc/x86_64-apple-darwin23/13.2.0/cc1
#git lfs untrack libexec/gcc/x86_64-apple-darwin23/13.2.0/cc1obj
#git lfs untrack libexeclibexec/gcc/x86_64-apple-darwin23/13.2.0/cc1objplus
#git lfs untrack libexec/gcc/x86_64-apple-darwin23/13.2.0/cc1objplus
#git lfs untrack libexec/gcc/x86_64-apple-darwin23/13.2.0/cc1plus
#git lfs untrack libexec/gcc/x86_64-apple-darwin23/13.2.0/lto1
#git lfs status
#git lfs prune
#git lfs push origin main
#git filter-branch --force --index-filter \
#  "git rm --cached --ignore-unmatch x86_64-apple-darwin23-lto-dump cc1 cc1obj cc1objplus cc1objplus cc1plus lto1" \
#  --prune-empty --tag-name-filter cat -- --all
#git reflog expire --expire=now --all && git gc --prune=now --aggressive
#git push origin main --force
#git lfs ls-files

echo "Don't forget to add to the PATH"
echo 'export PATH=$PATH:$ROOTDIR/$OSXCROSSDIR/target/bin'

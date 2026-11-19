#!/bin/bash
# Builds hwlog.ko (kernel/hwlog/hwlog.c, stand-ins for Huawei's hwlog devices) against the phone's kernel build on the
# build PC ($HARMONY_BUILD/src/out/kernel) and signs it with the kernel's module key, as power/build-kstate.sh.
# Output: $WORK/out-kernel/hwlog.ko.
set -e
. "$(dirname "$0")/../../../build/env.sh"
HB=${HARMONY_BUILD:-$HOME/harmony-build}
cd $HB/src
O=$(realpath out/kernel)
B=$WORK/out-kernel/hwlog
mkdir -p $B
cp $COMMON/kernel/hwlog/hwlog.c $COMMON/kernel/hwlog/Kbuild $B/
make -s -C kernel O=$O M=$B ARCH=arm64 LLVM=1 LLVM_IAS=1 modules
llvm-strip --strip-debug $B/hwlog.ko
HASH=$(sed -n 's/^CONFIG_MODULE_SIG_HASH="\(.*\)"/\1/p' $O/.config)
$O/scripts/sign-file $HASH $O/certs/signing_key.pem $O/certs/signing_key.x509 $B/hwlog.ko
cp $B/hwlog.ko $WORK/out-kernel/hwlog.ko
modinfo -F vermagic $WORK/out-kernel/hwlog.ko

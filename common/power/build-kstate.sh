#!/bin/bash
# Builds kstate.ko (power/kstate.c, the kstate netlink channel for HarmonyOS's app freezer) against the phone's kernel
# build on the build PC ($HARMONY_BUILD/src/out/kernel) and signs it with the kernel's module key.
# Output: $WORK/out-power/kstate.ko.
set -e
. "$(dirname "$0")/../../build/env.sh"
HB=${HARMONY_BUILD:-$HOME/harmony-build}
cd $HB/src
O=$(realpath out/kernel)
B=$WORK/out-power/kstate
mkdir -p $B
cp $COMMON/power/kstate.c $COMMON/power/Kbuild $B/
make -s -C kernel O=$O M=$B ARCH=arm64 LLVM=1 LLVM_IAS=1 modules
llvm-strip --strip-debug $B/kstate.ko
HASH=$(sed -n 's/^CONFIG_MODULE_SIG_HASH="\(.*\)"/\1/p' $O/.config)
$O/scripts/sign-file $HASH $O/certs/signing_key.pem $O/certs/signing_key.x509 $B/kstate.ko
cp $B/kstate.ko $WORK/out-power/kstate.ko
modinfo -F vermagic $WORK/out-power/kstate.ko

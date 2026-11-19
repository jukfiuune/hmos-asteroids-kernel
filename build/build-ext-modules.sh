#!/bin/bash
# Builds the external Qualcomm/Nothing modules (TARGET_KERNEL_EXT_MODULES order from the device BoardConfig)
# against $HARMONY_BUILD/src/out/kernel on the build PC, the way LineageOS's kernel.mk does: each module through its
# own Makefile with KERNEL_SRC, a kernel-relative M and the kernel's O. Outputs land in out/kernel-modules/<module>,
# where the modules' Makefiles find each other's Module.symvers by relative path. TARGET_BOARD_PLATFORM comes from the
# Android build environment there; without it display, audio and others pick the pineapple configs.
# Usage: build-ext-modules.sh [module...]
HB=${HARMONY_BUILD:-$HOME/harmony-build}
cd $HB/src
K=$(realpath kernel); O=$(realpath out/kernel); MO=$(realpath out)/kernel-modules
LOGS=$(realpath out)/ext-logs; mkdir -p $LOGS
export ARCH=arm64 LLVM=1 LLVM_IAS=1 TARGET_BOARD_PLATFORM=volcano
MODS=${*:-$(sed -n '/^TARGET_KERNEL_EXT_MODULES/,/^$/p' device/BoardConfig.mk | grep -oE '(noth|qcom)/[^ \\]+')}
for m in $MODS; do
    rel=../kernel-modules/$m
    name=$(echo $m | tr / _)
    if make -C $K/$rel KERNEL_SRC=$K M=$rel O=$O OUT_DIR=$O -j10 > $LOGS/$name.log 2>&1; then
        echo "OK   $m ($(find $MO/$m -name '*.ko' | wc -l) ko)"
    else
        echo "FAIL $m: $(grep -m1 -E 'ERROR|error:' $LOGS/$name.log)"
    fi
done

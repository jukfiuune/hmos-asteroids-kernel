#!/bin/bash
# Builds the NullDebris asteroids kernel: gki_defconfig + pineapple_perf + asteroids_perf + harmony fragments.
set -e
HB=${HARMONY_BUILD:-$HOME/harmony-build}
cd $HB/src/kernel
export ARCH=arm64 LLVM=1 LLVM_IAS=1
O=../out/kernel
mkdir -p $O
make -s O=$O gki_defconfig
KCONFIG_CONFIG=$O/.config scripts/kconfig/merge_config.sh -m -O $O $O/.config \
    arch/arm64/configs/vendor/pineapple_perf.config arch/arm64/configs/vendor/asteroids_perf.config \
    arch/arm64/configs/vendor/harmony.config
make -s O=$O olddefconfig
make O=$O -j10 Image.gz modules  # DTBs are built separately (see dtmerge), they need KBUILD_DTC_INCLUDE
echo BUILD-OK

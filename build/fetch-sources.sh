#!/bin/bash
# Fetches every outside source the builds read into the build tree ($HARMONY_BUILD, default ~/harmony-build), at the
# commits this port was built from, and applies our changes to the ones we change (the kernel, the two Mesa trees).
# Safe to run again: what is already there is left alone. Run on the build machine after `./port sync` (it reads the
# patches from $HARMONY_BUILD/repo, i.e. from this repo). The donor firmware is not fetched here: README.md, step 2.
#
#   fetch-sources.sh [kernel|ohos|mesa|tools]...    (default: all)
set -e
HB=${HARMONY_BUILD:-$HOME/harmony-build}
REPO=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p $HB && cd $HB

pin() {  # pin <dir> <git url> <commit> [sparse paths...]: a checkout of exactly that commit
    local d=$1 url=$2 c=$3; shift 3
    if [ -d $d/.git ]; then echo "have $d"; return; fi
    mkdir -p $d && git -C $d init -q && git -C $d remote add origin $url
    [ $# -gt 0 ] && git -C $d sparse-checkout set "$@"
    git -C $d fetch -q --depth 1 origin $c 2>/dev/null || git -C $d fetch -q origin
    git -C $d -c advice.detachedHead=false checkout -q $c
    echo "got $d ($url @ ${c:0:12})"
}

kernel() {
    # NullDebris's LineageOS kernel for the Nothing Phone (3a), its devicetrees, the Qualcomm/Nothing modules and the
    # device tree (BoardConfig.mk lists the external modules).
    local ND=https://github.com/NullDebris
    pin src/kernel $ND/android_kernel_nothing_sm7635 3fd63df64c0f141412e17ef2faeeb695e85ba19d
    pin src/kernel-devicetrees $ND/android_kernel_nothing_sm7635-devicetrees e0eb1dc2235850f9f966bfb3294967d06c00a0f1
    pin src/kernel-modules $ND/android_kernel_nothing_sm7635-modules 0f520a49516e61c9de9092b6648ef5eb7c878b71
    pin src/device $ND/android_device_nothing_asteroids affc7d4a3e849f3ea399a1e7c2ef61c5ecfaa465
    ln -sfn kernel-devicetrees src/sm7635-devicetrees
    ln -sfn kernel-modules src/sm7635-modules
    # Qualcomm's PAL headers, for the audio bridge.
    pin src/arpal-lx https://git.codelinaro.org/clo/le/platform/vendor/qcom/opensource/arpal-lx.git \
        4cc35aa593b862548a9a118bf01355b15177c13b
    # What apply-ohos-ipc.sh diffs: OpenHarmony's 6.6 kernel against the upstream release it is based on.
    pin ref/ohos-kernel-6.6 https://gitee.com/openharmony/kernel_linux_6.6.git 05abe5cb2815cc7a2ebb64669a347884db467f6d
    if [ ! -d ref/linux-6.6.101 ]; then
        curl -sL https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.101.tar.xz | tar -xJ -C ref
    fi
    # Our changes, in order: OpenHarmony's binder and access token driver (a "harmony" branch with two commits), the
    # one-way binder sender pid, the haptic chip init, icnss2 without the modem's MAC; the config fragment.
    git -C src/kernel rev-parse --verify -q harmony >/dev/null || bash $REPO/common/kernel/apply-ohos-ipc.sh
    python3 $REPO/common/kernel/binder-oneway-pid.py src/kernel
    local p=$REPO/device/asteroids/vibrator/hapticdrv-chip-init.patch
    git -C src/kernel apply --check -R $p 2>/dev/null || git -C src/kernel apply $p
    p=$REPO/platform/qcom/wifi/icnss2-no-dms-mac.patch
    git -C src/kernel-modules apply --check -R $p 2>/dev/null || git -C src/kernel-modules apply $p
    cp $REPO/common/kernel/harmony.config src/kernel/arch/arm64/configs/vendor/harmony.config
}

ohos() {
    # The OpenHarmony 6.1 SDK: only its Linux native toolchain and sysroot are used (ohos/sdk/native).
    if [ ! -d ohos/sdk/native ]; then
        mkdir -p ohos/sdk
        [ -f ohos/sdk.tar.gz ] || curl -sL -o ohos/sdk.tar.gz \
            https://repo.huaweicloud.com/openharmony/os/6.1-Release/ohos-sdk-windows_linux-public.tar.gz
        local t; t=$(mktemp -d)
        tar -xzf ohos/sdk.tar.gz -C $t
        unzip -q "$(find $t -path '*linux*' -name 'native-linux-*.zip' | head -1)" -d ohos/sdk
        rm -rf $t
    fi
    # Headers and IDL the HDI services, VDIs and fallbacks build against.
    local G=https://gitee.com/openharmony
    pin ohos/src/drivers_interface $G/drivers_interface.git 83043df7f5b93e65a21599966f6e043f13211325
    pin ohos/src/drivers_peripheral $G/drivers_peripheral.git c4579da480cc524ad6229d90c5c5fd65d675ceab
    pin ohos/src/drivers_hdf_core $G/drivers_hdf_core.git c5b2c04a7303f0e7d203a56dd064be59a25ee4de
    pin ohos/src/commonlibrary_c_utils $G/commonlibrary_c_utils.git 634d5c9d0aa3642f697938c7e5706e53ec069ba1
    pin ohos/src/communication_ipc $G/communication_ipc.git ec9f4f4bd643adb8d0c9b9baef42a50816cf62d3
    pin ohos/src/hiviewdfx_hilog $G/hiviewdfx_hilog.git edbfe7c162e1d3be5838dbb8d6f88080a01206a5
    pin ohos/src/graphic_graphic_2d $G/graphic_graphic_2d.git 46a11e91c9709942196ad2a7afea2e0fcd1349f3
    pin ohos/src/graphic_graphic_surface $G/graphic_graphic_surface.git 58fda6c05148e122f5d4ed146d34f85727b36a65
    pin ohos/src/multimedia_camera_framework $G/multimedia_camera_framework.git 9873dd191f59efda885bc06897acf9b0660de8f2
    pin ohos/src/third_party_bounds_checking_function $G/third_party_bounds_checking_function.git \
        2ae82839ecaaa7d031e66ccbd2076d671acfd615
    pin ohos/src/third_party_openmax $G/third_party_openmax.git 8e512e6ea60daab56c5a47fb8a2468f483f59d2b
    pin ohos/src/security_huks $G/security_huks.git 3d7efd14182eb3486eee6e0db0a176b6cfb43e11 \
        build frameworks interfaces/inner_api/huks_standard/main/include services utils
    pin ohos/src-new/drivers_interface $G/drivers_interface.git 83043df7f5b93e65a21599966f6e043f13211325
    pin ohos/src-new/graphic_graphic_2d $G/graphic_graphic_2d.git 46a11e91c9709942196ad2a7afea2e0fcd1349f3
    pin ohos/third_party/bounds_checking_function $G/third_party_bounds_checking_function.git \
        2ae82839ecaaa7d031e66ccbd2076d671acfd615
}

mesa() {
    # Turnip: Mesa main plus our patch (docs/gpu.md); Zink and EGL: OpenHarmony's Mesa fork plus ours.
    mkdir -p m2
    if [ ! -d m2/mesa/.git ]; then
        pin m2/mesa https://gitlab.freedesktop.org/mesa/mesa.git 0d234946736de1f290f31eba328b1385be949afc
        git -C m2/mesa apply $REPO/platform/qcom/gpu/patches/turnip-asteroids.patch
    fi
    if [ ! -d m2/mesa-ohos/.git ]; then
        pin m2/mesa-ohos https://gitee.com/openharmony/third_party_mesa3d.git ea74a6339917390657db153cb9792f9ccac9f5ae
        git -C m2/mesa-ohos apply $REPO/platform/qcom/gpu/patches/zink-ohos.patch
    fi
}

tools() {
    # hap-sign-tool (its dist/ holds the jar and the profile templates sign-hap.sh uses).
    pin tools/hapsigner https://github.com/openharmony/developtools_hapsigner.git 24ef0c843d94f68d16975cac42e377f31def48c6
    # erofs-utils: build/build-erofs-utils.sh fetches and builds it.
    [ -x tools/erofs-utils/bin/mkfs.erofs ] || bash $REPO/build/build-erofs-utils.sh
    # Alpine's static busybox (M1's shell and tools) and, for M1's DHCP server, busybox-extras and musl's loader.
    local A=https://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64 t
    if [ ! -f tools/busybox/x/bin/busybox.static ]; then
        mkdir -p tools/busybox/x
        curl -sL -o tools/busybox/busybox-static-1.37.0-r31.apk $A/busybox-static-1.37.0-r31.apk
        echo "965777e06b94bf11981d5f4ecdfcd577879f4b0dda544294d1dd3f72b217bc75  tools/busybox/busybox-static-1.37.0-r31.apk" |
            sha256sum -c --quiet
        tar -xzf tools/busybox/busybox-static-1.37.0-r31.apk -C tools/busybox/x 2>/dev/null
    fi
    if [ ! -f m2/m2root.tar.gz ]; then
        t=$(mktemp -d); mkdir -p $t/m2root m2
        local musl
        musl=$(curl -sL $A/APKINDEX.tar.gz | tar -xzO APKINDEX | awk -F: '/^P:/{p=$2} /^V:/{if(p=="musl")print $2}' | head -1)
        for pkg in busybox-extras-1.37.0-r31 musl-$musl; do
            curl -sL $A/$pkg.apk | tar -xz -C $t/m2root 2>/dev/null
        done
        tar -czf m2/m2root.tar.gz -C $t m2root && rm -rf $t
    fi
}

for step in ${*:-kernel ohos mesa tools}; do $step; done
echo "sources in $HB"

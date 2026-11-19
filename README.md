# Kernel changes for HarmonyOS NEXT on the Nothing Phone (3a)

The kernel side of the hmos-asteroids port: what NullDebris's LineageOS 6.6 kernel for the Nothing Phone (3a)
(github.com/NullDebris/android_kernel_nothing_sm7635 and its devicetrees and modules) needs to run HarmonyOS.

| Change | File |
|---|---|
| OpenHarmony's binder extensions and access token driver (CONFIG_ACCESS_TOKENID, CONFIG_BINDER_SENDER_INFO, CONFIG_BINDER_TRANSACTION_PROC_BRIEF), ported from OpenHarmony-v6.0-Release's kernel_linux_6.6 | `common/kernel/apply-ohos-ipc.sh` |
| One-way binder calls report their sender pid, as HarmonyOS's kernel does | `common/kernel/binder-oneway-pid.py` |
| The haptic driver initializes the chip once its firmware is there | `device/asteroids/vibrator/hapticdrv-chip-init.patch` |
| icnss2 goes on without the modem's MAC address | `platform/qcom/wifi/icnss2-no-dms-mac.patch` |
| Config fragment | `common/kernel/harmony.config` |
| hwlog and kstate modules | `common/kernel/hwlog/`, `common/power/` |

Fetch the trees at the pinned commits and apply all of it, then build (on Linux x86-64 with clang/LLVM):

```bash
export HARMONY_BUILD=~/harmony-build        # where the sources and outputs go
build/fetch-sources.sh kernel                # only the kernel step; the other steps belong to the port repository
build/build-kernel.sh && build/build-ext-modules.sh
```

The port repository (hmos-asteroids) runs the same steps itself and builds the boot images from the result
(`build/assemble-boot.sh`). Details: [docs/kernel.md](docs/kernel.md).

Licence: GPL-2.0 ([LICENSE](LICENSE)), as the kernel.

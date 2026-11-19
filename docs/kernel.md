# Kernel and modules

## Sources (build PC, `~/harmony-build/src`)

NullDebris LineageOS for this phone, built from source with every Qualcomm module, so the stock KMI doesn't matter:

- Kernel `android_kernel_nothing_sm7635`, branch `6.6/lineage-24.0` (release `6.6.142-android15-8-4k`).
- Modules `-modules` `6.6/lineage-24.0`; device trees `-devicetrees` `6.6/lineage-23.2`; device config
  `android_device_nothing_asteroids` `6.6/lineage-24.0` (module load order, fstab, init rc, firmware paths, cmdline).
- Blobs: gitlab `nulldebris/proprietary_vendor_nothing_asteroids`, branch `lineage-24.0` (GPU firmware gen80300
  SQE/GMU/zap, Wi-Fi and ADSP firmware). The LFS radio images are never flashed.
- Laptop copies: `~/Documents/iosasteroids/refs/nulldebris-*`. Build scripts: `build/build-kernel.sh`,
  `build/build-ext-modules.sh`.

## Our changes

| Change | Where | Why |
|---|---|---|
| OHOS IPC (access token, binder changes) | `common/kernel/apply-ohos-ipc.sh` | samgr and every service check callers' tokens |
| `CONFIG_PID_NS=y` | `common/kernel/harmony.config` (PC: `arch/arm64/configs/vendor/harmony.config`) | ArkWeb's renderer spawns with CLONE_NEWPID |
| One-way binder sender pid | `common/kernel/binder-oneway-pid.py` (applied uncommitted in the PC's tree, so the release string and vermagic stay) | render_service drops non-system apps' one-way commits from pid 0 ([apps.md](apps.md)) |
| `arm64.nopauth` on the command line | `build/assemble-boot.sh` | apps' Cangjie runtimes sign return addresses with PACIASP; Kirin has no PAC, this SoC does, and their stack walk then crashes |
| icnss2 without the modem's MAC wait | `platform/qcom/wifi/icnss2-no-dms-mac.patch` | Wi-Fi came up too late for wifi_manager ([wifi.md](wifi.md)) |
| RT6010 haptic chip init | `device/asteroids/vibrator/hapticdrv-chip-init.patch` | [vibration.md](vibration.md) |
| kstate (netlink unit 30) | `common/power/kstate.c` (module) | the background-app freezer ([power.md](power.md)) |
| hwlog_exception, hwlog_jank, hwlog_dubai (misc devices) | `common/kernel/hwlog/hwlog.c` (module, after kstate in vendor_dlkm's list) | the anco container requires them; writes dropped, reads block (as /dev/null, hiview_anco spun on hwlog_jank) |

Previous boot.img: `images/boot-pre-oneway.img`, `boot-pre-nopauth.img`; `images/prev-nopidns/` keeps only
boot.img from before PID_NS.

The kernel has no hmdfs, sharefs, fscrypt, `/dev/code_sign`, qos_ctrl/RTG or Huawei's memcg extensions; each is
worked around where it mattered ([storage.md](storage.md), [apps.md](apps.md), [performance.md](performance.md)).

## Modules

M1 loads 341 modules (vendor_boot + recovery + vendor_dlkm lists and dependencies). prep.sh replaces three at runtime:
icnss2 (patched; only while WPSS is off), hapticdrv (patched; after M1's module made its one firmware attempt) and
loads kstate while the WLAN driver is out, so kstate gets netlink unit 30 first.

## Facts (carried over from the iOS port, `~/Documents/iosasteroids`)

- ramoops: a fixed 4 MiB carve-out at 0x81f20000 (console and pmsg), survives a warm reset; the ABL/UEFI log is at
  0x81ce4000.
- Watchdog: Gunyah's virtual watchdog (`gh_virt_wdt`, first stage), 11 s bark, bite 3 s later. Never unload it.
- The kernel's firmware lookups follow init's root, so after the handoff firmware comes from HarmonyOS's `/vendor`
  (our overlay); `firmware_class.path` lists `/vendor/firmware` and `/vendor/firmware_mnt/image`.

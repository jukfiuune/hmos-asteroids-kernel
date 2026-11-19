# Licences

This port's own code is under the Apache License 2.0 ([LICENSE](LICENSE)), unless a file says otherwise. These parts
come from elsewhere or carry their own licence:

| Where | What | Licence |
|---|---|---|
| `common/kernel/hwlog/hwlog.c`, `common/power/kstate.c` | kernel modules | GPL-2.0 (SPDX headers) |
| `common/kernel/apply-ohos-ipc.sh`, `binder-oneway-pid.py`, `device/asteroids/vibrator/hapticdrv-chip-init.patch`, `platform/qcom/wifi/icnss2-no-dms-mac.patch` | changes to the Linux kernel and its modules; the result is GPL-2.0 like the kernel | GPL-2.0 |
| Files with an Apache-2.0 header (HDI headers and IDL under `*/include/`, `platform/qcom/sensors/idl/`, HDI publishers) | derived from OpenHarmony | Apache-2.0 |
| Files with an MIT SPDX header | ours, or adapted from the sheng port (below) | MIT |
| `platform/qcom/audio/pd-mapper/` | Linaro's pd-mapper (github.com/linux-msm/pd-mapper) | BSD-3-Clause (headers) |
| `platform/qcom/gpu/patches/turnip-asteroids.patch`, `zink-ohos.patch`, `platform/qcom/gpu/zink/sheng/` | changes to Mesa | MIT, as Mesa |
| `*/sheng/` directories and files that name sheng | adapted from [AnyHarmonyOSNext/anyhmos_xiaomi_sheng](https://github.com/AnyHarmonyOSNext/anyhmos_xiaomi_sheng) (commit 8095782), a HarmonyOS port to a Xiaomi tablet | that project has no licence file; credit to its authors |
| `device/asteroids/wifi/WCNSS_qcom_cfg.ini` | the WLAN driver's settings file from Android's vendor partition | Qualcomm's; a configuration file as shipped in public device trees |
| `common/apps/petrelgram-*.patch`, `harlgram-api21.patch` (apps repo) | changes to Petrelgram and Harlgram | the licence of each app |

Not in this repository, and fetched or extracted by the scripts instead: Huawei's HarmonyOS firmware (the donor),
Huawei's preload package and Android container image, Nothing OS images and firmware (including the haptics
firmware), Google apps (MindTheGapps), the Linux kernel and modules, OpenHarmony's SDK and sources, and Mesa. Their
licences are their owners'; nothing here grants rights to them.

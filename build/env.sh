# Sourced by the build scripts on the build PC: where things are.
#   HB      the build tree: $HARMONY_BUILD, default ~/harmony-build (README.md lists what goes in it)
#   REPO    this repo ($HARMONY_BUILD/repo, which port sync keeps current); sources come only from here
#   WORK    the builds' working tree: outputs (out-*), the Mesa trees and their build directories, sysroots and link
#           stubs (ohos-link, ohos-stage, bionic-link), the stage the asteroids partition is laid out from. Called m2
#           for history (the Mesa build directories hold absolute paths into it).
#   COMMON, QCOM, DEVICE, DONORDIR   the repo's layers
HB=${HARMONY_BUILD:-$HOME/harmony-build}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$HB/m2
COMMON=$REPO/common
QCOM=$REPO/platform/qcom
DEVICE=$REPO/device/asteroids
DONORDIR=$REPO/donor/pura70proplus-7.0.0.107

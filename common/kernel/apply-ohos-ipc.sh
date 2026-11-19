#!/bin/bash
# Ports OpenHarmony's binder extensions and access token driver (CONFIG_ACCESS_TOKENID, CONFIG_BINDER_SENDER_INFO,
# CONFIG_BINDER_TRANSACTION_PROC_BRIEF) from OpenHarmony-6.0-Release's kernel_linux_6.6 into our NullDebris 6.6
# kernel, on a "harmony" branch, and commits the result. Run on the build PC.
#
# The OpenHarmony changes are taken as diffs against upstream v6.6.101 (their base), so Android's own binder changes
# in our tree stay. Left out on purpose: binder.c hunk 11 (a BINDER_WRITE_READ size check, not a HarmonyOS feature)
# and the Kconfig "config ANDROID" wrapper (our tree already has one). The task_struct fields and the fork() copy are
# added by hand because OpenHarmony's sched.h/fork.c diffs also carry unrelated scheduler and memory features.
set -e
HB=${HARMONY_BUILD:-$HOME/harmony-build}
R=$HB/ref
O=$R/ohos-kernel-6.6
U=$R/linux-6.6.101
K=$HB/src/kernel
cd $K
git rev-parse --verify -q harmony >/dev/null && { echo "branch harmony exists; refusing to re-apply"; exit 1; }
git checkout -q -b harmony
git -c user.name=harmony-port -c user.email=harmony@localhost commit -q --allow-empty -m "harmony: branch point"

hunks() {  # diff of one file against upstream, without the hunk numbers given in $2 (space separated)
    diff -u --label a/$1 --label b/$1 $U/$1 $O/$1 | python3 -I -c '
import sys
skip = {int(x) for x in sys.argv[1].split()}
n = 0
keep = True
for line in sys.stdin:
    if line.startswith("@@"):
        n += 1
        keep = n not in skip
    if line.startswith(("---", "+++")) or keep:
        sys.stdout.write(line)
' "$2"
}

hunks drivers/android/binder.c "11" | patch -p1 --fuzz=3 --no-backup-if-mismatch
# Hunk 11 changed binder_ioctl_write_read() to take cmd; keep its caller on the old signature.
sed -i 's/ret = binder_ioctl_write_read(filp, cmd, arg, thread);/ret = binder_ioctl_write_read(filp, arg, thread);/' \
    drivers/android/binder.c
hunks drivers/android/binder_internal.h "" | patch -p1 --fuzz=3 --no-backup-if-mismatch
# With fuzz, hunks 1 and 3 land in Android's binder_proc_wrap and inside a comment. Put the fields where
# OpenHarmony has them: binder_thread after is_dead, binder_transaction after lock.
python3 -I - <<'EOF'
p = "drivers/android/binder_internal.h"
s = open(p).read()
thr = ("#ifdef CONFIG_ACCESS_TOKENID\n\tstruct access_token tokens;\n#endif /* CONFIG_ACCESS_TOKENID */\n"
       "#ifdef CONFIG_BINDER_SENDER_INFO\n\t__u64 sender_pid_nr;\n#endif /* CONFIG_BINDER_SENDER_INFO */\n")
tok = "#ifdef CONFIG_ACCESS_TOKENID\n\tu64 sender_tokenid;\n\tu64 first_tokenid;\n#endif /* CONFIG_ACCESS_TOKENID */\n"
assert s.count(thr) == 1 and s.count(tok) == 1
s = s.replace(thr, "", 1).replace(tok, "", 1)
i = s.index("struct binder_thread {")
j = s.index("\tbool is_dead;\n", i) + len("\tbool is_dead;\n")
s = s[:j] + thr + s[j:]
i = s.index("struct binder_transaction {")
j = s.index("\tspinlock_t lock;\n", i) + len("\tspinlock_t lock;\n")
s = s[:j] + tok + s[j:]
open(p, "w").write(s)
EOF
hunks include/uapi/linux/android/binder.h "" | patch -p1 --fuzz=3 --no-backup-if-mismatch

# Kconfig: the two binder options (OpenHarmony's text), inside our existing menu.
python3 -I - <<'EOF'
p = "drivers/android/Kconfig"
s = open(p).read()
add = '''
config BINDER_TRANSACTION_PROC_BRIEF
	bool "Brief debug info for binder transaction and proc"
	depends on ANDROID_BINDER_IPC
	default n
	help
	  Enable binder optimization

config BINDER_SENDER_INFO
	bool "Get binder sender info"
	depends on ANDROID_BINDER_IPC
	default y

endmenu'''
i = s.rindex("endmenu")
open(p, "w").write(s[:i].rstrip("\n") + "\n" + add + s[i + len("endmenu"):])
EOF

# The access token driver, hooked into drivers/. NWEBSPAWN_UID lives in OpenHarmony's include/linux/uidgid.h;
# define it in the driver's own header instead of changing a core header.
cp -r $O/drivers/accesstokenid drivers/
python3 -I - <<'EOF'
p = "drivers/accesstokenid/access_tokenid.h"
s = open(p).read()
add = "\n/* From OpenHarmony include/linux/uidgid.h: nwebspawn may set tokens for render processes. */\n#ifndef NWEBSPAWN_UID\n#define NWEBSPAWN_UID KUIDT_INIT(3081)\n#endif\n"
i = s.rindex("#endif")
open(p, "w").write(s[:i] + add + "\n" + s[i:])
EOF
grep -q accesstokenid drivers/Kconfig || sed -i 's|^source "drivers/android/Kconfig"|&\n\nsource "drivers/accesstokenid/Kconfig"|' drivers/Kconfig
grep -q accesstokenid drivers/Makefile || echo 'obj-$(CONFIG_ACCESS_TOKENID)		+= accesstokenid/' >> drivers/Makefile

# task_struct fields and the copy on fork, as in OpenHarmony.
python3 -I - <<'EOF'
p = "include/linux/sched.h"
s = open(p).read()
anchor = "\t/*\n\t * New fields for task_struct should be added above here"
assert anchor in s and "ftoken" not in s
s = s.replace(anchor, "#ifdef CONFIG_ACCESS_TOKENID\n\tu64\t\t\t\ttoken;\n\tu64\t\t\t\tftoken;\n#endif\n\n" + anchor, 1)
open(p, "w").write(s)
p = "kernel/fork.c"
s = open(p).read()
anchor = "\ttsk->stack_canary = get_random_canary();\n#endif\n"
assert anchor in s and "ftoken" not in s
s = s.replace(anchor, anchor + "#ifdef CONFIG_ACCESS_TOKENID\n\ttsk->token = orig->token;\n\ttsk->ftoken = 0;\n#endif\n", 1)
open(p, "w").write(s)
EOF

cat > arch/arm64/configs/vendor/harmony.config <<'EOF'
# HarmonyOS userspace: binder access tokens and sender info (OpenHarmony kernel features).
CONFIG_ACCESS_TOKENID=y
CONFIG_BINDER_SENDER_INFO=y
EOF

git add -A
git -c user.name=harmony-port -c user.email=harmony@localhost commit -q -m "harmony: OpenHarmony binder access tokens and sender info

Ported from OpenHarmony-6.0-Release kernel_linux_6.6 (05abe5c): CONFIG_ACCESS_TOKENID
(drivers/accesstokenid, task_struct token/ftoken, fork copy), CONFIG_BINDER_SENDER_INFO,
CONFIG_BINDER_TRANSACTION_PROC_BRIEF and the BINDER_FEATURE_SET / GET_ACCESS_TOKEN /
GET_SENDER_INFO ioctls. Binder.c hunk 11 (write_read size check) is not included."
git log --oneline -2
git diff --stat HEAD~1 | tail -3

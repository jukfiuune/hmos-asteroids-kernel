#!/usr/bin/env python3
"""Makes binder report the sender pid of one-way transactions, as HarmonyOS's own kernel does.

    binder-oneway-pid.py <kernel tree>        (on the build PC, ~/harmony-build/src/kernel)

Linux binder hands a one-way transaction to the receiver with sender_pid 0 (only synchronous calls carry the sender).
Huawei's HongMeng kernel gives the real pid, and the donor's services rely on it: render_service checks every UI
command of a non-system app against the caller's pid (RSClientToRenderConnectionStub COMMIT_TRANSACTION,
IsCallingPidValid), and app commits are one-way, so every third-party app's frames were dropped. OpenHarmony's Linux
kernel has the same 0 (sheng's port added a one-way pid to his kernel for the same reason).

Android's binder already records the sending process for every transaction (t->from_pid, from_tid); the OpenHarmony
port (apply-ohos-ipc.sh) had moved that under CONFIG_BINDER_TRANSACTION_PROC_BRIEF, which is off, so it is set again
for one-way calls and replies, and binder_thread_read reports it for one-way calls: as trd->sender_pid in the
receiver's pid namespace, and as sender_pid_nr for OpenHarmony's BINDER_GET_SENDER_INFO.

Applied uncommitted on purpose: the kernel release string (and so the module vermagic) carries the tree's commit.
"""
import os
import sys

p = os.path.join(sys.argv[1], "drivers/android/binder.c")
s = open(p).read()

edits = [(
    """	} else {
		t->from = NULL;
#ifdef CONFIG_BINDER_TRANSACTION_PROC_BRIEF
		t->from_pid = thread->proc->pid;
		t->from_tid = thread->pid;
#endif
	}
""",
    """	} else {
		t->from = NULL;
		/* As Android: one-way calls and replies keep their sender (reported in binder_thread_read). */
		t->from_pid = thread->proc->pid;
		t->from_tid = thread->pid;
	}
"""), (
    """		} else {
			trd->sender_pid = 0;
#ifdef CONFIG_BINDER_SENDER_INFO
			binder_inner_proc_lock(thread->proc);
			thread->sender_pid_nr = 0;
			binder_inner_proc_unlock(thread->proc);
#endif
		}
""",
    """		} else if ((t->flags & TF_ONE_WAY) && t->from_pid > 0) {
			/*
			 * One-way call: report the sender, as HarmonyOS's kernel does. Its services check one-way callers
			 * (render_service drops a non-system app's UI commits that come from pid 0).
			 */
			rcu_read_lock();
			trd->sender_pid = pid_vnr(find_pid_ns(t->from_pid, &init_pid_ns));
			rcu_read_unlock();
#ifdef CONFIG_BINDER_SENDER_INFO
			binder_inner_proc_lock(thread->proc);
			thread->sender_pid_nr = t->from_pid;
			binder_inner_proc_unlock(thread->proc);
#endif
		} else {
			trd->sender_pid = 0;
#ifdef CONFIG_BINDER_SENDER_INFO
			binder_inner_proc_lock(thread->proc);
			thread->sender_pid_nr = 0;
			binder_inner_proc_unlock(thread->proc);
#endif
		}
""")]
for old, new in edits:
    if s.count(new) == 1:
        continue
    if s.count(old) != 1:
        sys.exit("%s: expected code not found once (a different tree?)" % p)
    s = s.replace(old, new)
open(p, "w").write(s)
print("binder: one-way sender pid")

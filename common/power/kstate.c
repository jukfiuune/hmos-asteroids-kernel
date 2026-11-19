// SPDX-License-Identifier: GPL-2.0
/*
 * asteroids kstate: the kernel side of HarmonyOS's "kstate" channel (netlink unit 30), which Huawei's kernel provides
 * and ours doesn't. resource_schedule_service's suspend manager (the background-app freezer) and lowpower_manager talk
 * to it; without it the suspend manager's init fails ("Cannot init netlink manager") and no app is ever frozen.
 *
 * Every message, both ways, is a netlink header (type 0) and a 16-byte header {tag, src channel, dst channel, length}
 * followed by the data. From userspace: tag 1 checks the channel (we answer tag 1), tag 4 sets the events a socket
 * wants (a u32 mask; the suspend manager asks for 8 | 16), tag 5 carries commands (freeze notices, Wi-Fi, idle,
 * sleep), which we ignore. To userspace, tag 4 events: {u32 mask, 12 bytes unused, text}. We send two kinds, for
 * tasks in a freezing or frozen cgroup only, and the suspend manager thaws the target:
 *   mask 8:  "[PID %d KILLED][SIG %d]"                           a signal sent to a frozen process
 *   mask 16: "[TPID %d CALLED][PID %d][1][0][%u][0][%u][%s]"     a synchronous binder call to a frozen process
 *            (called, caller, isFreeze, binder type, transaction flags, level, code, interface)
 * Asynchronous calls aren't reported: they queue in binder and are read on thaw, as on Android. The format was read
 * from libsuspend_manager_service.z.so (netlink_manager.cpp, kstate_callback.cpp).
 *
 * The hooks run under binder's and the signal code's locks, so events go through a small ring and a work item.
 * Load it before the WLAN driver: qcacld also creates unit 30 (its "cesium" socket, unused here; failing to create it
 * is not fatal for the driver).
 */
#include <linux/module.h>
#include <linux/netlink.h>
#include <linux/freezer.h>
#include <linux/sched/signal.h>
#include <linux/workqueue.h>
#include <net/sock.h>
#include <trace/hooks/binder.h>
#include <trace/hooks/signal.h>
#include "binder_internal.h"

#define KSTATE_UNIT 30
#define TAG_CONNECT 1
#define TAG_KSTATE 4
#define MASK_SIGNAL 8
#define MASK_BINDER 16
#define MAX_CLIENTS 8
#define RING 64
#define TEXT 160

struct ks_hdr {
	u32 tag, src, dst, len;
};

struct ks_event {
	u32 mask;
	pid_t pid, from;
	u32 sig_or_flags, code;
};

static struct sock *nl;
static DEFINE_SPINLOCK(lock);
static struct {
	u32 portid, mask;
} clients[MAX_CLIENTS];
static struct ks_event ring[RING];
static unsigned int head, tail;
static atomic_t dropped;
/* Events delivered so far, in /sys/module/kstate/parameters. */
static unsigned int signal_events, binder_events;
module_param(signal_events, uint, 0444);
module_param(binder_events, uint, 0444);

static bool is_frozen(struct task_struct *p)
{
	/* frozen() isn't exported; it is this test. */
	return p && ((READ_ONCE(p->__state) & TASK_FROZEN) || freezing(p));
}

static int ks_send(u32 portid, u32 tag, const void *data, u32 len, gfp_t gfp)
{
	struct ks_hdr h = { tag, 4, 8, len };
	struct nlmsghdr *nlh;
	struct sk_buff *skb = nlmsg_new(sizeof(h) + len, gfp);

	if (!skb)
		return -ENOMEM;
	nlh = nlmsg_put(skb, 0, 0, 0, sizeof(h) + len, 0);
	if (!nlh) {
		kfree_skb(skb);
		return -EMSGSIZE;
	}
	memcpy(nlmsg_data(nlh), &h, sizeof(h));
	if (len)
		memcpy((char *)nlmsg_data(nlh) + sizeof(h), data, len);
	return netlink_unicast(nl, skb, portid, MSG_DONTWAIT);
}

static void ks_flush(struct work_struct *w)
{
	struct {
		u32 mask;
		u8 unused[12];
		char text[TEXT];
	} data;
	struct ks_event e;
	unsigned long flags;
	int i, n, ret;

	for (;;) {
		spin_lock_irqsave(&lock, flags);
		if (head == tail) {
			spin_unlock_irqrestore(&lock, flags);
			break;
		}
		e = ring[tail++ % RING];
		spin_unlock_irqrestore(&lock, flags);

		memset(&data, 0, sizeof(data));
		data.mask = e.mask;
		if (e.mask == MASK_SIGNAL)
			n = scnprintf(data.text, TEXT, "[PID %d KILLED][SIG %u]", e.pid, e.sig_or_flags);
		else
			n = scnprintf(data.text, TEXT, "[TPID %d CALLED][PID %d][1][0][%u][0][%u][unknown]",
				      e.pid, e.from, e.sig_or_flags, e.code);
		for (i = 0; i < MAX_CLIENTS; i++) {
			u32 portid;

			spin_lock_irqsave(&lock, flags);
			portid = clients[i].mask & e.mask ? clients[i].portid : 0;
			spin_unlock_irqrestore(&lock, flags);
			if (!portid)
				continue;
			ret = ks_send(portid, TAG_KSTATE, &data, 16 + n + 1, GFP_KERNEL);
			if (ret >= 0)
				*(e.mask == MASK_SIGNAL ? &signal_events : &binder_events) += 1;
			if (ret == -ECONNREFUSED) {  /* the socket is gone */
				spin_lock_irqsave(&lock, flags);
				if (clients[i].portid == portid)
					clients[i].portid = clients[i].mask = 0;
				spin_unlock_irqrestore(&lock, flags);
			}
		}
	}
	n = atomic_xchg(&dropped, 0);
	if (n)
		pr_warn("kstate: %d events dropped\n", n);
}
static DECLARE_WORK(ks_work, ks_flush);

static bool wanted(u32 mask)
{
	int i;

	for (i = 0; i < MAX_CLIENTS; i++)
		if (READ_ONCE(clients[i].mask) & mask)
			return true;
	return false;
}

static void queue(u32 mask, pid_t pid, pid_t from, u32 sig_or_flags, u32 code)
{
	unsigned long flags;
	unsigned int i;

	spin_lock_irqsave(&lock, flags);
	/* A burst of calls to one frozen process needs one thaw. */
	for (i = tail; i != head; i++)
		if (ring[i % RING].mask == mask && ring[i % RING].pid == pid)
			goto out;
	if (head - tail >= RING) {
		atomic_inc(&dropped);
		goto out;
	}
	ring[head++ % RING] = (struct ks_event){ mask, pid, from, sig_or_flags, code };
out:
	spin_unlock_irqrestore(&lock, flags);
	schedule_work(&ks_work);
}

static void on_binder(void *unused, struct task_struct *caller, struct task_struct *proc_task,
		      struct task_struct *thread_task, int node_debug_id, struct binder_transaction *t,
		      bool pending_async)
{
	if (!t || (t->flags & TF_ONE_WAY) || !wanted(MASK_BINDER))
		return;
	if (!is_frozen(proc_task) && !is_frozen(thread_task))
		return;
	queue(MASK_BINDER, task_tgid_nr(proc_task), task_tgid_nr(caller), t->flags, t->code);
}

static void on_signal(void *unused, int sig, struct task_struct *killer, struct task_struct *dst)
{
	if (!dst || !wanted(MASK_SIGNAL) || !is_frozen(dst))
		return;
	queue(MASK_SIGNAL, task_tgid_nr(dst), killer ? task_tgid_nr(killer) : 0, sig, 0);
}

static void input(struct sk_buff *skb)
{
	struct nlmsghdr *nlh = nlmsg_hdr(skb);
	u32 portid = NETLINK_CB(skb).portid;
	struct ks_hdr *h;
	unsigned long flags;
	int i, slot = -1;
	u32 mask;

	if (skb->len < NLMSG_HDRLEN + sizeof(*h) || nlh->nlmsg_len > skb->len ||
	    nlh->nlmsg_len < NLMSG_HDRLEN + sizeof(*h))
		return;
	h = nlmsg_data(nlh);
	if (h->tag == TAG_CONNECT) {
		ks_send(portid, TAG_CONNECT, NULL, 0, GFP_KERNEL);
		return;
	}
	if (h->tag != TAG_KSTATE || h->len < sizeof(u32) || nlh->nlmsg_len < NLMSG_HDRLEN + sizeof(*h) + sizeof(u32))
		return;  /* tag 5 commands: nothing to do here */
	mask = *(u32 *)(h + 1);
	spin_lock_irqsave(&lock, flags);
	for (i = 0; i < MAX_CLIENTS; i++) {
		if (clients[i].portid == portid) {
			slot = i;
			break;
		}
		if (slot < 0 && !clients[i].portid)
			slot = i;
	}
	if (slot >= 0) {
		clients[slot].portid = portid;
		clients[slot].mask = mask;
	}
	spin_unlock_irqrestore(&lock, flags);
	pr_info("kstate: port %u mask %u%s\n", portid, mask, slot < 0 ? " (no free slot)" : "");
}

static int __init kstate_init(void)
{
	struct netlink_kernel_cfg cfg = { .input = input };
	int ret;

	nl = netlink_kernel_create(&init_net, KSTATE_UNIT, &cfg);
	if (!nl) {
		pr_err("kstate: netlink unit %d is taken\n", KSTATE_UNIT);
		return -EBUSY;
	}
	ret = register_trace_android_vh_binder_proc_transaction(on_binder, NULL);
	if (!ret)
		ret = register_trace_android_vh_do_send_sig_info(on_signal, NULL);
	if (ret) {
		unregister_trace_android_vh_binder_proc_transaction(on_binder, NULL);
		netlink_kernel_release(nl);
		return ret;
	}
	pr_info("kstate: netlink unit %d ready\n", KSTATE_UNIT);
	return 0;
}

static void __exit kstate_exit(void)
{
	unregister_trace_android_vh_do_send_sig_info(on_signal, NULL);
	unregister_trace_android_vh_binder_proc_transaction(on_binder, NULL);
	tracepoint_synchronize_unregister();
	cancel_work_sync(&ks_work);
	netlink_kernel_release(nl);
}

module_init(kstate_init);
module_exit(kstate_exit);
MODULE_DESCRIPTION("HarmonyOS kstate netlink channel for the app freezer");
MODULE_LICENSE("GPL");

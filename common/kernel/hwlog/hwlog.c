// SPDX-License-Identifier: GPL-2.0
/*
 * asteroids hwlog: stand-ins for Huawei's log devices, /dev/hwlog_exception, /dev/hwlog_jank and /dev/hwlog_dubai.
 * Huawei's kernel has a log driver behind them; services write exception, jank and power records there for Huawei's
 * log collector, which we don't run. The anco Android container requires the three nodes (config.zip's must-exist
 * devices), and its hiview_anco reads hwlog_jank. As /dev/null they made that reader spin a core (a read returns 0 at
 * once, poll says readable). Here writes are accepted and dropped, reads wait until the reader is interrupted, poll
 * never reports input, and ioctls answer ENOTTY.
 */
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/poll.h>
#include <linux/sched/signal.h>
#include <linux/wait.h>

static DECLARE_WAIT_QUEUE_HEAD(never);

static ssize_t hwlog_read(struct file *file, char __user *buf, size_t count, loff_t *pos)
{
	if (file->f_flags & O_NONBLOCK)
		return -EAGAIN;
	wait_event_interruptible(never, false);
	return -ERESTARTSYS;
}

static ssize_t hwlog_write(struct file *file, const char __user *buf, size_t count, loff_t *pos)
{
	return count;
}

static __poll_t hwlog_poll(struct file *file, poll_table *wait)
{
	poll_wait(file, &never, wait);
	return EPOLLOUT | EPOLLWRNORM;
}

static long hwlog_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	return -ENOTTY;
}

static const struct file_operations hwlog_fops = {
	.owner = THIS_MODULE,
	.read = hwlog_read,
	.write = hwlog_write,
	.poll = hwlog_poll,
	.unlocked_ioctl = hwlog_ioctl,
	.compat_ioctl = hwlog_ioctl,
	.llseek = noop_llseek,
};

static struct miscdevice hwlog_devs[] = {
	{ .minor = MISC_DYNAMIC_MINOR, .name = "hwlog_exception", .fops = &hwlog_fops, .mode = 0666 },
	{ .minor = MISC_DYNAMIC_MINOR, .name = "hwlog_jank", .fops = &hwlog_fops, .mode = 0666 },
	{ .minor = MISC_DYNAMIC_MINOR, .name = "hwlog_dubai", .fops = &hwlog_fops, .mode = 0666 },
};

static int __init hwlog_init(void)
{
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(hwlog_devs); i++) {
		ret = misc_register(&hwlog_devs[i]);
		if (ret) {
			while (i--)
				misc_deregister(&hwlog_devs[i]);
			return ret;
		}
	}
	return 0;
}

static void __exit hwlog_exit(void)
{
	int i;

	for (i = ARRAY_SIZE(hwlog_devs); i--;)
		misc_deregister(&hwlog_devs[i]);
}

module_init(hwlog_init);
module_exit(hwlog_exit);
MODULE_DESCRIPTION("asteroids stand-ins for Huawei's hwlog devices");
MODULE_LICENSE("GPL");

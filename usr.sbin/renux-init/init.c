/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2026 The Renux Project.
 *
 * Minimal init for the Renux boot ISOs: open the console and exec /bin/sh.
 * This lets the kernel-only boot media drop to a root shell without a full
 * userland.
 */
#include <fcntl.h>
#include <unistd.h>

int
main(void)
{
	int fd;

	setsid();
	fd = open("/dev/console", O_RDWR);
	if (fd >= 0) {
		dup2(fd, 0);
		dup2(fd, 1);
		dup2(fd, 2);
		if (fd > 2)
			close(fd);
	}
	execl("/bin/sh", "sh", "-i", (char *)NULL);
	for (;;)
		sleep(1000);
}

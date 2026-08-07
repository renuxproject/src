/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2026 The Renux Project.
 *
 * Minimal init for the Renux boot ISOs: spawn an interactive /bin/sh on the
 * boot console plus the video (/dev/ttyv0) and serial (/dev/cuau0) consoles
 * when present.  This lets the kernel-only boot media give a root shell on
 * the display and over the serial port at the same time.
 */
#include <fcntl.h>
#include <unistd.h>

static const char *consoles[] = {
	"/dev/console",
	"/dev/ttyv0",
	"/dev/cuau0",
	NULL
};

static void
spawn_shell(int fd)
{
	pid_t pid;

	pid = fork();
	if (pid != 0)
		return;
	/* Child: give the shell this console as stdin/out/err. */
	setsid();
	dup2(fd, 0);
	dup2(fd, 1);
	dup2(fd, 2);
	if (fd > 2)
		close(fd);
	execl("/bin/sh", "sh", "-i", (char *)NULL);
	for (;;)
		sleep(1000);
}

int
main(void)
{
	const char **cp;
	int fd;

	setsid();
	for (cp = consoles; *cp != NULL; cp++) {
		fd = open(*cp, O_RDWR);
		if (fd < 0)
			continue;
		spawn_shell(fd);
		close(fd);
	}
	/* Never exit, or the kernel panics. */
	for (;;)
		sleep(1000);
}

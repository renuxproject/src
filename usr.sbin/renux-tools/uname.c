#include <stdio.h>
#include <string.h>
#include <sys/utsname.h>
int main(int argc, char **argv) {
	struct utsname u;
	int all = argc > 1 && argv[1][0] == '-' && strchr(argv[1], 'a');
	if (uname(&u) < 0) return 1;
	if (all)
		printf("%s %s %s %s %s\n", u.sysname, u.nodename,
		    u.release, u.version, u.machine);
	else
		puts(u.sysname);
	return 0;
}

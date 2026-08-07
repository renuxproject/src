#include <stdio.h>
#include <unistd.h>
int main(void) {
	printf("uid=%d(root) gid=%d\n", (int)getuid(), (int)getgid());
	return 0;
}

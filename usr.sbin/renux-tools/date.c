#include <stdio.h>
#include <time.h>
int main(void) {
	time_t t = time(NULL);
	struct tm *tm = localtime(&t);
	char b[64];
	strftime(b, sizeof b, "%a %b %e %H:%M:%S %Y", tm);
	puts(b);
	return 0;
}

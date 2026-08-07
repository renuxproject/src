#include <stdio.h>
#include <unistd.h>
int main(void) { char b[256]; gethostname(b, sizeof b); puts(b); return 0; }

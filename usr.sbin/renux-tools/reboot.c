#include <unistd.h>
#include <sys/reboot.h>
int main(void) { sync(); return reboot(RB_AUTOBOOT); }

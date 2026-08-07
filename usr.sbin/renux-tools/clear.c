#include <unistd.h>
int main(void) { return write(1, "\033[H\033[2J", 7) < 0 ? 1 : 0; }

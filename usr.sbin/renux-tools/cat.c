#include <stdio.h>
int main(int argc, char **argv) {
	int i, c;
	FILE *f;
	if (argc < 2) {
		while ((c = getchar()) != EOF) putchar(c);
		return 0;
	}
	for (i = 1; i < argc; i++) {
		f = fopen(argv[i], "r");
		if (f == NULL) { perror(argv[i]); return 1; }
		while ((c = fgetc(f)) != EOF) putchar(c);
		fclose(f);
	}
	return 0;
}

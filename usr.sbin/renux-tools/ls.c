#include <stdio.h>
#include <dirent.h>
int main(int argc, char **argv) {
	const char *d = argc > 1 ? argv[1] : ".";
	struct dirent *e;
	DIR *dd = opendir(d);
	if (dd == NULL) { perror(d); return 1; }
	while ((e = readdir(dd)) != NULL) {
		if (argc <= 1 && e->d_name[0] == '.')
			continue;
		puts(e->d_name);
	}
	closedir(dd);
	return 0;
}

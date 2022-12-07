#include <stdlib.h>
#include <argp.h>
#include <string.h>

#define TC_EASY_OK 0
#define TC_EASY_ERROR 1

void usage()
{
	printf("Usage: tc-easy [add | remove]\n");
	exit(TC_EASY_ERROR);
}

int main(int argc, char *argv[])
{
	if (argc <= 1)
	{
		usage();
	}

	for (int i = 1; i < argc; i++)
	{
		if (strcmp(argv[i], "add") == 0)
		{
			char *interface = argv[++i];
		}
		else if (strcmp(argv[i], "rm") == 0)
		{
			char *interface = argv[++i];
		}
		else
		{
			printf("Unknown subcommand %s\n", argv[i]);
			usage();
		}
	}

	exit(TC_EASY_OK);
}
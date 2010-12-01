#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
//#include <arpa/inet.h>

int main(int argc, char **argv)
{
	int s = socket(AF_LOCAL, SOCK_DGRAM, 0);
	if ( s < 0 )
	{
		perror("socket");
		return -1;
	}

	int nl = 0;
	char *msg = NULL;
	if ( argc == 2 ) {
		msg = argv[1];
	} else if ( argc == 3 && strcmp(argv[1], "-n") == 0 ) {
		nl = 1;
		msg = argv[2];
	} else {
		fprintf(stderr, "Usage: %s [-n] message", argv[0]);
		return -1;
	}

	struct sockaddr_un svr;
	memset(&svr, 0, sizeof(svr));
	svr.sun_family = AF_LOCAL;
	sprintf(svr.sun_path, "/tmp/ui_server.sock");

	int len = strlen(msg) + 2;
	char *buf = (char *)malloc(len);
	*buf = nl != 0 ? 'B' : 'A';
	strcpy(buf+1, msg);

	if ( sendto(s, buf, len, 0, (struct sockaddr *)&svr, sizeof(svr)) < 0 ) {
		perror("sendto");
		return -1;
	}

	return 0;
}


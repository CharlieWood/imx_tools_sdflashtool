#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>

#include "minui.h"

#define CHAR_WIDTH 10
#define CHAR_HEIGHT 18

#define RED           0xff0000ff
#define GREEN         0x00ff00ff
#define BLUE          0x0000ffff

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static int width = 0;
static int height = 0;
static int rows = 0;

static int top_y = 0;
static int cur_y = 0;
static int cur_x = 0;

struct Text {
	int x;
	int y;
	unsigned int color;
	const char *msg;
	struct Text *next;
};

static struct Text *text = NULL;

static void clear()
{
	gr_color(0, 0, 0, 255);
	gr_fill(0, 0, width, height);
}

static void ui_init()
{
	gr_init();

	width = gr_fb_width();
	height = gr_fb_height();
	rows = height / CHAR_HEIGHT;

	top_y = 0;
	cur_x = 0;
	cur_y = CHAR_HEIGHT;

	clear();
	gr_flip();
}

static void set_color(unsigned int color)
{
	gr_color((color >> 24) & 0xff, (color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff);
}

static void draw_message()
{
	clear();

	struct Text *t = text;
	for ( ; t != NULL; t = t->next ) {
		int x = t->x;
		int y = t->y - top_y;

		if ( y > height )
			continue;
		else if ( y < CHAR_HEIGHT )
			break;
		else {
			set_color(t->color);
			gr_text(x, y, t->msg);
		}
	}
}

static pthread_mutex_t prog_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t prog_cond = PTHREAD_COND_INITIALIZER;
static int prog_enable = 0;
static int prog_x = 0;
static int prog_y = 0;
static int prog_step = 0;
static const char *prog_strs[] = { "-", "\\", "/", };

static void start_progress(int x, int y)
{
	pthread_mutex_lock(&prog_lock);
	prog_x = x;
	prog_y = y;
	prog_enable = 1;
	pthread_cond_signal(&prog_cond);
	pthread_mutex_unlock(&prog_lock);
}

static void stop_progress()
{
	prog_enable = 0;
}

static void *progress_thread(void *data)
{
	pthread_detach(pthread_self());

	int s = socket(AF_LOCAL, SOCK_DGRAM, 0);
	if ( s < 0 )
	{
		perror("socket");
		return NULL;
	}

	struct sockaddr_un svr;
	memset(&svr, 0, sizeof(svr));
	svr.sun_family = AF_LOCAL;
	sprintf(svr.sun_path, "/tmp/ui_server.sock");

	char ch = 'C';

	for ( ; ; ) {
		pthread_mutex_lock(&prog_lock);
		while ( prog_enable == 0 )
			pthread_cond_wait(&prog_cond, &prog_lock);
		pthread_mutex_unlock(&prog_lock);

		while ( prog_enable ) {
			if ( sendto(s, &ch, 1, 0, (struct sockaddr *)&svr, sizeof(svr)) < 0 ) {
				perror("sendto");
				return NULL;
			}
			usleep(300000);
		}
	}
	return NULL;
}

static void show_message(const char *msg, int nl)
{
	pthread_mutex_lock(&g_lock);

	if ( cur_y > height ) {
		// scroll screen
		top_y += CHAR_HEIGHT;
		draw_message();

		cur_y -= CHAR_HEIGHT;
	}

	unsigned int color = 0;
	if ( cur_x != 0 ) {
		if ( strcmp(msg, "FAIL") == 0 )
			color = RED;
		else
			color = GREEN;

		stop_progress();
		gr_color(0, 0, 0, 255);
		gr_fill(prog_x, prog_y - CHAR_HEIGHT, prog_x + CHAR_WIDTH, prog_y);
	} else {
		color = BLUE;
	}
	
	set_color(color);
	gr_text(cur_x, cur_y, msg);
	gr_flip();

	pthread_mutex_unlock(&g_lock);

	struct Text *t = (struct Text *)malloc(sizeof(struct Text));
	t->x = cur_x;
	t->y = cur_y + top_y;
	t->color = color;
	t->msg = strdup(msg);
	t->next = text;
	text = t;

	if ( nl ) {
		cur_y += CHAR_HEIGHT;
		cur_x = 0;
	} else {
		cur_x += CHAR_WIDTH * (strlen(msg) + 3);
		start_progress(cur_x, cur_y);
	}
}

int main()
{
	ui_init();

	pthread_t tid;
	pthread_create(&tid, NULL, progress_thread, NULL);

	char buf[128];

	int s = socket(AF_LOCAL, SOCK_DGRAM, 0);
	if ( s < 0 )
	{
		snprintf(buf, 128, "ERROR: create socket failed, errno = %d", errno);
		show_message(buf, 1);
		perror("socket");
		return -1;
	}

	unlink("/tmp/ui_server.sock");

	struct sockaddr_un svr;
	memset(&svr, 0, sizeof(svr));
	svr.sun_family = AF_LOCAL;
	strcpy(svr.sun_path, "/tmp/ui_server.sock");
	if ( bind(s, (struct sockaddr *)&svr, sizeof(svr)) < 0 )
	{
		snprintf(buf, 128, "ERROR: bind failed: errno = %d", errno);
		show_message(buf, 1);
		perror("bind");
		return -1;
	}

	for ( ; ; )
	{
		char buf[1024];
		struct sockaddr_un cli;
		socklen_t cli_len = sizeof(cli);
		int n = recvfrom(s, buf, 1024, 0, (struct sockaddr *)&cli, &cli_len);
		if ( n < 0 )
		{
			snprintf(buf, 128, "ERROR: recvfrom failed: errno = %d", errno);
			show_message(buf, 1);
			perror("recvfrom");
			continue;
		}

		//printf("Recved from %s:  %s\n", cli.sun_path, buf);
		switch ( buf[0] ) {
			case 'A':
				show_message(buf + 1, 1);
				break;
			case 'B':
				show_message(buf + 1, 0);
				break;
			case 'C':
				if ( prog_enable ) {
					++prog_step;
					prog_step = (prog_step) % (sizeof(prog_strs) / sizeof(prog_strs[0]));
					gr_color(0, 0, 0, 255);
					gr_fill(prog_x, prog_y - CHAR_HEIGHT, prog_x + CHAR_WIDTH, prog_y);
					set_color(BLUE);
					gr_text(prog_x, prog_y, prog_strs[prog_step]);
					gr_flip();
				}
				break;
			default:
				break;
		}
	}
	return 0;
}


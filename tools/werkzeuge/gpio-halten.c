// Haelt eine GPIO-Leitung auf einem Pegel, bis das Programm beendet wird (GPIO-cdev v2).
// Fuer Tests ohne libgpiod auf dem Tablet. Statisch bauen:
//   aarch64-linux-gnu-gcc -static -O2 -o gpio-halten gpio-halten.c
// Aufruf (als root): gpio-halten <Teil des Chip-Labels> <Leitung> <0|1>
//   z. B. gpio-halten 7022000 7 1   (r_pio, PL7 auf high)
#include <fcntl.h>
#include <glob.h>
#include <linux/gpio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc != 4) {
		fprintf(stderr, "Aufruf: %s <Label-Teil> <Leitung> <0|1>\n", argv[0]);
		return 2;
	}
	glob_t g;
	if (glob("/dev/gpiochip*", 0, NULL, &g) != 0) {
		fprintf(stderr, "keine /dev/gpiochip*\n");
		return 1;
	}
	for (size_t i = 0; i < g.gl_pathc; i++) {
		int fd = open(g.gl_pathv[i], O_RDWR);
		if (fd < 0)
			continue;
		struct gpiochip_info info = { 0 };
		if (ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &info) == 0 && strstr(info.label, argv[1])) {
			struct gpio_v2_line_request req = { 0 };
			req.offsets[0] = (unsigned int)atoi(argv[2]);
			req.num_lines = 1;
			strcpy(req.consumer, "gpio-halten");
			req.config.flags = GPIO_V2_LINE_FLAG_OUTPUT;
			req.config.num_attrs = 1;
			req.config.attrs[0].attr.id = GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES;
			req.config.attrs[0].attr.values = atoi(argv[3]) ? 1 : 0;
			req.config.attrs[0].mask = 1;
			if (ioctl(fd, GPIO_V2_GET_LINE_IOCTL, &req) < 0) {
				perror("GPIO_V2_GET_LINE_IOCTL");
				return 1;
			}
			printf("%s (%s): Leitung %s = %s, halte ...\n", g.gl_pathv[i], info.label, argv[2], argv[3]);
			fflush(stdout);
			for (;;)
				pause();
		}
		close(fd);
	}
	fprintf(stderr, "kein gpiochip mit \"%s\" im Label\n", argv[1]);
	return 1;
}

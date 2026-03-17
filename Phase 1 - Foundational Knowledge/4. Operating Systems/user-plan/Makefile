# User plan example: Lectures 1–9 (OS)
CFLAGS ?= -Wall -Wextra -O2 -pthread
LDFLAGS ?= -pthread

rt_demo: rt_demo.c
	$(CC) $(CFLAGS) -o $@ rt_demo.c $(LDFLAGS)

clean:
	rm -f rt_demo

.PHONY: clean

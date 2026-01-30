CC ?= gcc
CFLAGS ?= -Wall -Wextra -O2
PREFIX ?= /usr/local

SRCS = src/main.c
OBJS = $(SRCS:.c=.o)
TARGET = hello-c

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(TARGET) $(OBJS)

install: $(TARGET)
	install -D -m 755 $(TARGET) $(DESTDIR)$(PREFIX)/bin/$(TARGET)

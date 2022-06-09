# Makefile for Proxy Lab 
#
# You may modify this file any way you like (except for the handin
# rule). You instructor will type "make" on your specific Makefile to
# build your proxy from sources.

CC = gcc
CFLAGS = -g -Wall
LDFLAGS = -lpthread
EXCLUDED_CFLAGS = -Wno-format-overflow -Wno-restrict

all: proxy

lib.o: lib.c lib.h
	$(CC) $(CFLAGS) -c lib.c

proxy.o: proxy.c lib.h
	$(CC) $(CFLAGS) $(EXCLUDED_CFLAGS) -c proxy.c

proxy: proxy.o lib.o
	$(CC) $(CFLAGS) $(EXCLUDED_CFLAGS) proxy.o lib.o -o proxy $(LDFLAGS)

clean:
	rm -f *~ *.o proxy core *.tar *.zip *.gzip *.bzip *.gz


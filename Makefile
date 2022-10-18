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

rio.o: rio/rio.c rio/rio.h
	$(CC) $(CFLAGS) -c rio/rio.c

sock_interface.o: sock_interface/sock_interface.c sock_interface/sock_interface.h
	$(CC) $(CFLAGS) -c sock_interface/sock_interface.c

memlib.o: cache/memlib.c cache/memlib.h
	$(CC) $(CFLAGS) -c cache/memlib.c

mm.o: cache/mm.c cache/mm.h
	$(CC) $(CFLAGS) -c cache/mm.c

cache.o: cache/cache.c cache/cache.h
	$(CC) $(CFLAGS) -c cache/cache.c

proxy.o: proxy.c
	$(CC) $(CFLAGS) $(EXCLUDED_CFLAGS) -c proxy.c

proxy: rio.o sock_interface.o memlib.o mm.o cache.o proxy.o
	$(CC) $(CFLAGS) $(EXCLUDED_CFLAGS) rio.o sock_interface.o cache.o memlib.o mm.o proxy.o -o $@ $(LDFLAGS)

run: proxy
	./proxy 4000

debug: all

clean:
	rm -f *~ *.o proxy core *.tar *.zip *.gzip *.bzip *.gz


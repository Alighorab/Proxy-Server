#ifndef CACHE_h
#define CACHE_h

#include "mm.h"
#include <semaphore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_CACHE_SIZE  1049000     /* 1MB total cache size */
#define MAX_OBJECT_SIZE 102400      /* 1KB cache object size */
#define CACHE_LINES 100

typedef struct cache_line {
    unsigned char valid;
    unsigned long long tag;
    unsigned long long time;
    size_t content_length;
    char *response_hdr;
    void *content;
} CacheLine, *CacheLinePtr;

typedef struct cache {
    CacheLine cache_set[CACHE_LINES];
    sem_t write_mutex, readcnt_mutex;
    unsigned long long readcnt;
} Cache, *CachePtr;

void cache_init(CachePtr cp);

ssize_t cache_read(CachePtr cp, char *request,
        char **response_hdrs, char **content);

void cache_write(CachePtr cp, char *request,
        char *response_hdrs, char *content, size_t content_length);

size_t cache_size(CachePtr cp);
#endif

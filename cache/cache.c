#include "cache.h"
#include <semaphore.h>
#include <stdlib.h>
#include <string.h>

static unsigned long long generate_tag(const char *request);
static int find_empty_line(CachePtr cp);
static unsigned int find_victim(CachePtr cp);
static void free_line(CachePtr cp, unsigned int idx);
static int find_line(CachePtr cp, unsigned long long tag);

static unsigned long long time = 0;
sem_t time_mutex;

void
cache_init(CachePtr cp)
{
    cp->readcnt = 0;
    sem_init(&cp->readcnt_mutex, 0, 1);
    sem_init(&cp->write_mutex, 0, 1);
    sem_init(&time_mutex, 0, 1);
    memset(cp->cache_set, 0, sizeof(cp->cache_set));
    mm_init();
}

ssize_t
cache_read(CachePtr cp, char *request, char **response_hdrs, char **content)
{
    int idx;
    unsigned long long tag = generate_tag(request);
    ssize_t content_length;

    sem_wait(&cp->readcnt_mutex);
    cp->readcnt++;
    if (cp->readcnt == 1) { /* First in */
        sem_wait(&cp->write_mutex);
    }
    sem_post(&cp->readcnt_mutex);

    if ((idx = find_line(cp, tag)) < 0) {
        content_length = -1;
    } else {
        *response_hdrs = strdup(cp->cache_set[idx].response_hdr);
        content_length = cp->cache_set[idx].content_length;
        *content = malloc(content_length);
        memcpy(*content, cp->cache_set[idx].content, content_length);

        sem_wait(&time_mutex);
        cp->cache_set[idx].time = time++;
        sem_post(&time_mutex);
    }

    sem_wait(&cp->readcnt_mutex);
    cp->readcnt--;
    if (cp->readcnt == 0) { /* Last out */
        sem_post(&cp->write_mutex);
    }
    sem_post(&cp->readcnt_mutex);

    return content_length;
}

void
cache_write(CachePtr cp, char *request, char *response_hdrs, char *content,
            size_t content_length)
{
    size_t len = content_length + strlen(response_hdrs);
    if (content_length > MAX_OBJECT_SIZE ||
        (cache_size(cp) + len) >= MAX_CACHE_SIZE) {
        /* TO-DO: Remove element from cache */
        return;
    }
    int idx;
    unsigned long long tag = generate_tag(request);
    char *response_hdrs_ptr = mm_malloc(strlen(response_hdrs));
    char *content_ptr = mm_malloc(content_length);
    sem_wait(&cp->write_mutex);

    idx = find_empty_line(cp);

    cp->cache_set[idx].valid = 1;
    cp->cache_set[idx].tag = tag;
    cp->cache_set[idx].content_length = content_length;
    cp->cache_set[idx].response_hdr = response_hdrs_ptr;
    strcpy(cp->cache_set[idx].response_hdr, response_hdrs);
    cp->cache_set[idx].content = content_ptr;
    memcpy(cp->cache_set[idx].content, content, content_length);

    sem_wait(&time_mutex);
    cp->cache_set[idx].time = time++;
    sem_post(&time_mutex);

    sem_post(&cp->write_mutex);
}

size_t
cache_size(CachePtr cp)
{
    return mm_size();
}

static unsigned long long
generate_tag(const char *request)
{
    size_t len = strlen(request);
    unsigned long hash = 5381;
    char *hash_str;

    /* Build the string that will be hashed */
    hash_str = (char *)malloc(len + 1);
    hash_str[0] = '\0';
    strcpy(hash_str, request);

    for (int i = 0; i < len; i++)
        hash = ((hash << 5) + hash) + hash_str[i]; /* hash * 33 + c */

    free(hash_str);
    return hash;
}

static int
find_line(CachePtr cp, unsigned long long tag)
{
    int i;
    for (i = 0; i < CACHE_LINES; i++) {
        if (cp->cache_set[i].valid == 1 && cp->cache_set[i].tag == tag) {
            return i;
        }
    }
    return -1;
}

static int
find_empty_line(CachePtr cp)
{
    int idx;
    for (idx = 0; idx < CACHE_LINES; idx++) {
        if (cp->cache_set[idx].valid == 0) {
            return idx;
        }
    }
    idx = find_victim(cp);
    return idx;
}

static unsigned int
find_victim(CachePtr cp)
{
    /* LRU algorithm */
    int lru = 0;
    int t = cp->cache_set[0].time;
    int i;
    for (i = 1; i < CACHE_LINES; i++) {
        if (cp->cache_set[i].time < t) {
            t = cp->cache_set[i].time;
            lru = i;
        }
    }
    free_line(cp, lru);
    return lru;
}

static void
free_line(CachePtr cp, unsigned int idx)
{
    mm_free(cp->cache_set[idx].response_hdr);
    mm_free(cp->cache_set[idx].content);
}

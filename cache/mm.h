#ifndef MM_h
#define MM_h
    
#include <stdio.h>

int mm_init (void);
void *mm_malloc (size_t size);
void mm_free (void *ptr);
void *mm_realloc(void *ptr, size_t size);

#endif

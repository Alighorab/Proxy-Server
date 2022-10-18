#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "memlib.h"
#include "mm.h"

/*
 * If NEXT_FIT defined use next fit search, else use first-fit search
 */
#define NEXT_FIT

#define WSIZE 4          /* Word and header/footer size (bytes) */
#define DSIZE 8          /* Double word size (bytes) */
#define ALIGNMENT DSIZE  /* single word (4) or double word (8) alignment */
#define BTAGS_SIZE DSIZE /* size of header and footer */
#define MIN_BLKSIZE (ALIGNMENT + BTAGS_SIZE)
#define ALIGN(size)                                                            \
    (((size) + (ALIGNMENT - 1)) &                                              \
     ~0x7) /* rounds up to the nearest multiple of ALIGNMENT */
#define SIZE_T_SIZE (ALIGN(sizeof(size_t)))

#define CHUNKSIZE (1 << 12) /* Extend heap by this amount (bytes) */

#define MAX(x, y) ((x) > (y) ? (x) : (y))
#define MIN(x, y) ((x) < (y) ? (x) : (y))

/* Pack a size and allocated bit into a word */
#define PACK(size, alloc) ((size) | (alloc))

/* Read and write a word at address p */
#define GET(p) (*(unsigned int *)(p))
#define PUT(p, val) (*(unsigned int *)(p) = (val))

/* Read the size and allocated fields from address p */
#define GET_SIZE(p) (GET(p) & ~0x7)
#define GET_ALLOC(p) (GET(p) & 0x1)

/* Given block ptr bp, compute address of its header and footer */
#define HDRP(bp) ((char *)(bp)-WSIZE)
#define FTRP(bp) ((char *)(bp) + GET_SIZE(HDRP(bp)) - DSIZE)

/* Given block ptr bp, compute address of next and previous blocks */
#define NEXT_BLKP(bp) ((char *)(bp) + GET_SIZE(((char *)(bp)-WSIZE)))
#define PREV_BLKP(bp) ((char *)(bp)-GET_SIZE(((char *)(bp)-DSIZE)))

static char *heap_listp = 0; /* Pointer to first block */
#ifdef NEXT_FIT
static char *rover; /* Next fit rover */
#endif

static void *extend_heap(size_t words);
static void place(void *bp, size_t asize);
static void *find_fit(size_t asize);
static void *coalesce(void *bp);

/*
 * mm_init - initialize the malloc package.
 */
int
mm_init(void)
{
    mem_init();
    /* Create the initial empty heap */
    if ((heap_listp = mem_sbrk(4 * WSIZE)) == (void *)-1)
        return -1;
    PUT(heap_listp, 0);                            /* Alignment padding */
    PUT(heap_listp + (1 * WSIZE), PACK(DSIZE, 1)); /* Prologue header */
    PUT(heap_listp + (2 * WSIZE), PACK(DSIZE, 1)); /* Prologue footer */
    PUT(heap_listp + (3 * WSIZE), PACK(0, 1));     /* Epilogue header */
    heap_listp += (2 * WSIZE);

#ifdef NEXT_FIT
    rover = heap_listp;
#endif
    /* Extend the empty heap with a free block of CHUNKSIZE bytes */
    if (extend_heap(CHUNKSIZE / WSIZE) == NULL)
        return -1;
    return 0;
}

/*
 * mm_malloc - Allocate a block by incrementing the brk pointer.
 *     Always allocate a block whose size is a multiple of the alignment.
 */
void *
mm_malloc(size_t size)
{
    size_t asize;      /* Adjusted block size */
    size_t extendsize; /* Amount to extend heap if no fit */
    char *bp;

    if (heap_listp == 0) {
        mm_init();
    }

    /* Ignore spurious requests */
    if (size == 0)
        return NULL;

    /* Adjust block size to include overhead and alignment reqs. */
    if (size <= ALIGNMENT)
        asize = MIN_BLKSIZE;
    else
        asize = ALIGN(size + BTAGS_SIZE);

    if ((bp = find_fit(asize)) == NULL) {
        extendsize = MAX(asize, CHUNKSIZE);
        if ((bp = extend_heap(extendsize / WSIZE)) == NULL) {
            return NULL;
        }
    }
    place(bp, asize);

    return bp;
}

/*
 * mm_free - Free a block and coalesce if neccessary
 */
void
mm_free(void *ptr)
{
    if (ptr == 0)
        return;

    size_t size = GET_SIZE(HDRP(ptr));

    PUT(HDRP(ptr), PACK(size, 0));
    PUT(FTRP(ptr), PACK(size, 0));
    coalesce(ptr);
}

/*
 * mm_realloc - reallocate 'ptr' block with new size 'size'.
 */
void *
mm_realloc(void *ptr, size_t size)
{
    size_t oldsize = 0, asize = 0, extendsize = 0;
    void *newptr = NULL;

    if (size == 0) {
        mm_free(ptr);
    }

    if (ptr == NULL) {
        return mm_malloc(size);
    }

    oldsize = GET_SIZE(HDRP(ptr));

    if (size <= ALIGNMENT)
        asize = MIN_BLKSIZE;
    else
        asize = ALIGN(size + BTAGS_SIZE);

    if ((newptr = find_fit(asize)) == NULL) {
        extendsize = MAX(asize, CHUNKSIZE);
        if ((newptr = extend_heap(extendsize / WSIZE)) == NULL) {
            return NULL;
        }
    }
    place(newptr, asize);
    memcpy(newptr, ptr, MIN(size, oldsize));
    mm_free(ptr);

    return newptr;
}

/*
 * mm_size - Return heap size
 */
size_t
mm_size(void)
{
    return mem_heapsize();
}

/*
 * coalesce - Boundary tag coalescing. Return ptr to coalesced block
 */
static void *
coalesce(void *bp)
{
    size_t prev_alloc = GET_ALLOC(FTRP(PREV_BLKP(bp)));
    size_t next_alloc = GET_ALLOC(HDRP(NEXT_BLKP(bp)));
    size_t size = GET_SIZE(HDRP(bp));

    if (prev_alloc && next_alloc) {
        return bp;
    }

    else if (prev_alloc && !next_alloc) {
        size += GET_SIZE(HDRP(NEXT_BLKP(bp)));
        PUT(HDRP(bp), PACK(size, 0));
        PUT(FTRP(bp), PACK(size, 0));
    }

    else if (!prev_alloc && next_alloc) {
        size += GET_SIZE(HDRP(PREV_BLKP(bp)));
        PUT(FTRP(bp), PACK(size, 0));
        PUT(HDRP(PREV_BLKP(bp)), PACK(size, 0));
        bp = PREV_BLKP(bp);
    }

    else {
        size += GET_SIZE(HDRP(PREV_BLKP(bp))) + GET_SIZE(FTRP(NEXT_BLKP(bp)));
        PUT(HDRP(PREV_BLKP(bp)), PACK(size, 0));
        PUT(FTRP(NEXT_BLKP(bp)), PACK(size, 0));
        bp = PREV_BLKP(bp);
    }
#ifdef NEXT_FIT
    /* Make sure the rover isn't pointing into the free block */
    /* that we just coalesced */
    if ((rover > (char *)bp) && (rover < NEXT_BLKP(bp)))
        rover = bp;
#endif
    return bp;
}

/*
 * extend_heap - Extend heap with free block and return its block pointer
 */
static void *
extend_heap(size_t words)
{
    char *bp;
    size_t size;

    /* Allocate an even number of words to maintain alignment */
    size = (words % 2) ? (words + 1) * WSIZE : words * WSIZE;
    if ((long)(bp = mem_sbrk(size)) == -1)
        return NULL;

    /* Initialize free block header/footer and the epilogue header */
    PUT(HDRP(bp), PACK(size, 0));         /* Free block header */
    PUT(FTRP(bp), PACK(size, 0));         /* Free block footer */
    PUT(HDRP(NEXT_BLKP(bp)), PACK(0, 1)); /* New epilogue header */

    /* Coalesce if the previous block was free */
    return coalesce(bp);
}

/*
 * place - Place block of asize bytes at start of free block bp
 *         and split if remainder would be at least minimum block size
 */
static void
place(void *bp, size_t asize)
{
    size_t size = GET_SIZE(HDRP(bp));
    if ((size - asize) >= (2 * DSIZE)) {
        PUT(HDRP(bp), PACK(asize, 1));
        PUT(FTRP(bp), PACK(asize, 1));
        PUT(HDRP(NEXT_BLKP(bp)), PACK((size - asize), 0));
        PUT(FTRP(NEXT_BLKP(bp)), PACK((size - asize), 0));
    } else {
        PUT(HDRP(bp), PACK(size, 1));
        PUT(FTRP(bp), PACK(size, 1));
    }
}

/*
 * find_fit - Find a fit for a block with asize bytes
 */
static void *
find_fit(size_t asize)
{
#ifdef NEXT_FIT
    /* Next fit search */
    char *oldrover = rover;

    /* Search from the rover to the end of list */
    for (; GET_SIZE(HDRP(rover)) > 0; rover = NEXT_BLKP(rover))
        if (!GET_ALLOC(HDRP(rover)) && (asize <= GET_SIZE(HDRP(rover))))
            return rover;

    /* search from start of list to old rover */
    for (rover = heap_listp; rover < oldrover; rover = NEXT_BLKP(rover))
        if (!GET_ALLOC(HDRP(rover)) && (asize <= GET_SIZE(HDRP(rover))))
            return rover;

    return NULL; /* no fit found */
#else
    /* First fit search */
    void *bp = heap_listp + DSIZE;
    size_t size = GET_SIZE(HDRP(bp));
    int alloc = GET_ALLOC(HDRP(bp));
    for (; size > 0; bp = NEXT_BLKP(bp)) {
        size = GET_SIZE(HDRP(bp));
        alloc = GET_ALLOC(HDRP(bp));
        if (size >= asize && !alloc) {
            return bp;
        }
    }
    return NULL; /* no fit found */
#endif
}

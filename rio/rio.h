#ifndef RIO_h
#define RIO_h

#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct sockaddr SA;
/* Persistent state for the robust I/O (Rio) package */
/* $begin rio_t */
#define RIO_BUFSIZE 8192
typedef struct {
    int rio_fd;                /* Descriptor for this internal buf */
    int rio_cnt;               /* Unread bytes in internal buf */
    char *rio_bufptr;          /* Next unread byte in internal buf */
    char rio_buf[RIO_BUFSIZE]; /* Internal buffer */
} Rio;
/* $end rio_t */

/* External variables */
extern int h_errno;    /* Defined by BIND for DNS errors */
extern char **environ; /* Defined by libc */

/* Rio (Robust I/O) package */
ssize_t rio_readn(int fd, void *usrbuf, size_t n);
ssize_t rio_writen(int fd, void *usrbuf, size_t n);
void rio_readinitb(Rio *rp, int fd);
ssize_t rio_readnb(Rio *rp, void *usrbuf, size_t n);
ssize_t rio_readlineb(Rio *rp, void *usrbuf, size_t maxlen);

#endif

#include "sock_interface.h"

int
open_clientfd(char* hostname, char* port)
{
    int clientfd, rc;
    struct addrinfo hints, *listp, *p;

    /* Get a list of potential server addresses */
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM; /* open a connection */
    hints.ai_flags = AI_NUMERICSERV; /* ... using a numeric port arg. */
    hints.ai_flags |= AI_ADDRCONFIG; /* Recommended for connections */
    if ((rc = getaddrinfo(hostname, port, &hints, &listp)) != 0) {
        fprintf(stderr, "getaddrinfo error: %s\n", gai_strerror(rc));
        return -1;
    }

    /* Walk the list for one that we can successfully connect to */
    for (p = listp; p; p = p->ai_next) {
        /* Create a socket discriptor */ 
        if ((clientfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) < 0) {
            continue; /* socket failed, try the next */
        }

        /* Connect to the server */
        if (connect(clientfd, p->ai_addr, p->ai_addrlen) != -1) {
            break; /* success */
        }
        close(clientfd); /* connection failed, try another */
    }

    /* Clean up */
    freeaddrinfo(listp);
    if (!p) { /* All connections failed */
        return -1;
    } else { /* The last connection succeeded */
        return clientfd;
    }
}

int
open_listenfd(char* port)
{
    struct addrinfo hints, *listp, *p;
    int listenfd, optval = 1, rc;

    /* Get a list of potential server addresses */
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM; /* Accept connections */
    hints.ai_flags = AI_PASSIVE | AI_ADDRCONFIG; /* ...on any IP address */
    hints.ai_flags |= AI_NUMERICSERV; /* ...using port number */
    if ((rc = getaddrinfo(NULL, port, &hints, &listp)) != 0) {
        fprintf(stderr, "getaddrinfo error: %s\n", gai_strerror(rc));
        return -1;
    }

    /* Walk the list for one that we can bind to */
    for (p = listp; p; p = p->ai_next) {
        /* Create a socket discriptor */
        if ((listenfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) < 0) {
            continue; /* Socket failed, try the next */
        }

        /* Eliminates "Adress already in use" error from bind */
        setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, 
                (const void*)&optval, sizeof(int));

        /* Bind the discriptor to the address */
        if (bind(listenfd, p->ai_addr, p->ai_addrlen) == 0) {
            break; /* Success */
        }
        close(listenfd); /* Bind failed, try the next */
    }

    /* Clean up */
    freeaddrinfo(listp);
    if (!p) { /* No address worked */
        return -1;
    }

    /* Make it a listening socket ready to accept connection requests */
    if (listen(listenfd, LISTENQ) < 0) {
        close(listenfd);
        return -1;
    }

    return listenfd;
}

#define _GNU_SOURCE
#include "cache/cache.h"
#include "rio/rio.h"
#include "sock_interface/sock_interface.h"

void *thread(void *vargp);
void read_request(int connfd, char *request, char *headers);
void append_version(char *request);
void parse_request(int connfd, char *request, char *headers, char *host,
                   char *port);
void read_requesthdrs(Rio *rp, char *request_headers);
void parse_uri(char *uri, char *hostname, char *port, char *request);
int serve_client(int connfd, char *request, char *headers, char **content);
void forward_response(int listenfd, char *headers, char *content,
                      int content_length);

static Cache cache;

int
main(int argc, char *argv[])
{
    int listenfd, *connfdp = NULL;
    struct sockaddr_storage clientaddr;
    socklen_t clientlen;
    pthread_t tid;

    if (argc != 2) {
        fprintf(stderr, "usage: %s <port>\n", argv[0]);
        exit(0);
    }

    if ((listenfd = open_listenfd(argv[1])) < 0) {
        fprintf(stderr, "%s: %s\n", "open_clientfd error", strerror(errno));
        exit(-1);
    }

    /* Ignore SIGPIPE signal if trying to write to a closed socket */
    signal(SIGPIPE, SIG_IGN);
    cache_init(&cache);

    while (1) {
        clientlen = sizeof(struct sockaddr_storage);
        connfdp = (int *)malloc(sizeof(int));

        if ((*connfdp = accept(listenfd, (SA *)&clientaddr, &clientlen)) < 0) {
            fprintf(stderr, "%s: %s\n", "accept error", strerror(errno));
            continue;
        }

        pthread_create(&tid, NULL, thread, (void *)connfdp);
    }

    return 0;
}

void *
thread(void *vargp)
{
    int connfd = *((int *)vargp), clientfd;
    pthread_detach(pthread_self());
    free(vargp);

    char buf[MAXLINE];
    char request[MAXLINE], headers[MAXLINE], host[MAXLINE], port[MAXLINE];
    char *content, *respone_hdrs;
    ssize_t content_length;

    read_request(connfd, request, headers);
    append_version(request);

    content_length = cache_read(&cache, request, &respone_hdrs, &content);
    if (content_length < 0) {
        strcpy(buf, request);
        parse_request(connfd, request, headers, host, port);

        if ((clientfd = open_clientfd(host, port)) < 0) {
            close(connfd);
            return NULL;
        }
        content_length = serve_client(clientfd, request, headers, &content);
        forward_response(connfd, headers, content, content_length);
        cache_write(&cache, buf, headers, content, content_length);
        printf("Using: %zu\r\nRemaining: %zu\r\n", cache_size(&cache),
               MAX_CACHE_SIZE - cache_size(&cache));
        free(content);
    } else {
        forward_response(connfd, respone_hdrs, content, content_length);
    }

    close(connfd);
    return NULL;
}

void
read_request(int connfd, char *request, char *headers)
{
    Rio rio;

    rio_readinitb(&rio, connfd);
    rio_readlineb(&rio, request, MAXLINE);
    read_requesthdrs(&rio, headers);
}

void
read_requesthdrs(Rio *rp, char *request_headers)
{
    char buf[MAXLINE];

    rio_readlineb(rp, buf, MAXLINE);
    sprintf(request_headers, "%s", buf);
    while (strcmp(buf, "\r\n")) {
        rio_readlineb(rp, buf, MAXLINE);
        sprintf(request_headers, "%s%s", request_headers, buf);
    }
}

void
append_version(char *request)
{
    char method[MAXLINE], uri[MAXLINE], version[MAXLINE];
    sscanf(request, "%s %s %s", method, uri, version);

    if (strcasecmp(version, "HTTP/1.0")) {
        sprintf(request, "%s %s %s\r\n", method, uri, "HTTP/1.0");
    }
}

void
parse_request(int connfd, char *request, char *headers, char *host, char *port)
{
    char path[MAXLINE], method[MAXLINE], uri[MAXLINE], version[MAXLINE];
    char buf[MAXLINE] = "";
    char *ptr;

    sscanf(request, "%s %s %s", method, uri, version);

    if (strcasecmp(method, "GET")) {
        fprintf(stderr, "method %s not implemented\n", method);
        *host = '\0';
        *port = '\0';
        return;
    }

    parse_uri(uri, host, port, path);
    sprintf(request, "%s %s %s\r\n", method, path, version);

    /* Build request headers */
    sprintf(buf, "Proxy-Connection: close\r\n");
    if ((ptr = strcasestr(headers, "connection: "))) {
        sprintf(buf, "%sConnection: close\r\n", buf);
    }
    if (!(ptr = strcasestr(headers, "host: "))) {
        sprintf(buf, "%sHost: %s\r\n", buf, host);
    }
    ptr = strcasestr(headers, "user-agent:");
    if (!ptr) {
        sprintf(buf, "%sUser-Agent: %s", buf,
                "Mozilla/5.0 (X11; Linux x86_64; rv:10.0.3) Gecko/20120305 "
                "Firefox/10.0.3\r\n");
    }
    /* Concatenate client headers with proxy headers */
    strcat(buf, headers);
    strcpy(headers, buf);

    printf("Request headers:\r\n");
    printf("%s", request);
    printf("%s", headers);
}

void
parse_uri(char *uri, char *hostname, char *port, char *path)
{
    char *ptr;

    ptr = strstr(uri, "http://");
    if (ptr) {
        /* remove http:// from uri */
        strcpy(uri, (ptr + strlen("http://")));
    } else {
        *hostname = '\0';
        *path = '\0';
        return;
    }

    if ((ptr = index(uri, ':'))) {
        *ptr = '\0';
        strcpy(hostname, uri);
        ptr++;
        uri = ptr;

        if ((ptr = index(uri, '/'))) {
            strncpy(port, uri, (int)(ptr - uri));
            *(port + (ptr - uri)) = '\0';
        } else {
            *hostname = '\0';
            *path = '\0';
            return;
        }

    } else {
        strcpy(port, "80");
        if ((ptr = index(uri, '/'))) {
            strncpy(hostname, uri, (int)(ptr - uri));
            *(hostname + (ptr - uri)) = '\0';
        } else {
            *hostname = '\0';
            *path = '\0';
            return;
        }
    }

    strcpy(path, ptr); /* Copy path */
}

int
serve_client(int clientfd, char *request, char *headers, char **content)
{
    Rio rio;
    char buf[MAXLINE], *ptr;
    int content_length = 0;

    rio_readinitb(&rio, clientfd);
    /* Send request and headers to server */
    rio_writen(clientfd, request, strlen(request));
    rio_writen(clientfd, headers, strlen(headers));

    /* Read response headers from server */
    rio_readlineb(&rio, buf, MAXLINE);
    sprintf(headers, "%s", buf);
    while (strcmp(buf, "\r\n")) {
        rio_readlineb(&rio, buf, MAXLINE);
        sprintf(headers, "%s%s", headers, buf);
    }

    printf("Response headers:\r\n");
    printf("%s", headers);

    /* Get the content length */
    if ((ptr = strcasestr(headers, "content-length: "))) {
        strcpy(buf, ptr);
        ptr = index(buf, '\r');
        *ptr = '\0';
        ptr = index(buf, ' ') + 1;

        if ((content_length = atoi(ptr)) > 0) {
            *content = malloc(content_length);
            rio_readnb(&rio, *content, content_length);
        }
    }

    return content_length;
}

void
forward_response(int connfd, char *headers, char *content, int content_length)
{
    rio_writen(connfd, headers, strlen(headers));
    if (content_length != 0) {
        rio_writen(connfd, content, content_length);
    }
}

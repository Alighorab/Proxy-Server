## Proxy Server

### Description
- A simple, multi-threaded `HTTP/1.0` proxy server.
- It's the 7th and last lab of [15-213: Introduction to Computer Systems](https://www.cs.cmu.edu/afs/cs.cmu.edu/academic/class/15213-f15/www/index.html).
- It uses a cache of size `1MB` to store reciently used requests.

### Implementation Details
[`proxy.c`](./proxy.c) contains:
- The `main` function which:
    1. **Opens** a listening desctiotor for requesting clients requests.
    2. **Initializes** the cache.
    3. **Accepts** a connection with each client.
    4. **Creates** a peer thread for each client.

- The `thread` function which:
    1. **Detaches** itself from the `main thread`.
    2. **Reads** client request and headers.
    3. If it's a valid request, it **searches** in the cache for the request, if present it sends it directly to the client
    4. If not present, then it **parses** the request.
    5. and **opens** a connection with the server the client requested.
    6. and **serves** the client, then forwards it content to it.
    7. lastly, it **caches** this request if it comes in the future.

### How to test it?

1. Compile and run
````
git clone https://github.com/Alighorab/Proxy-Server/
cd Proxy-Server/
make
./proxy <port> (e.g., 4000)
````

2. Connect to proxy
- Using `TELNET`:
````
telnet localhost <port>
````
- Or adjust your browser to content to proxy and content to http sites.
- **NOTE**: use these sites and what is similar to them only:
````
http://www.example.com
http://go.com
http://www.washington.edu
http://www.internic.com
`````

### Poject Files
````
├── cache
│  ├── cache.{c,h}: cache implementation.
│  ├── mm.{c,h}: dynaminc memory allocator to manage proxy cache.
│  └── memlib.{c,h}: a library for the allocator.
├── rio
│  └── rio.{c,h}: robust I/O package.
├── sock_interface
│  └── sock_interface.{c,h}: socket interface package.
├── Makefile
├── proxy.c: proxy implementation.
└── proxylab.pdf: proxy writeup.

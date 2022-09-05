#!/bin/bash


# Point values
MAX_BASIC=40
MAX_CONCURRENCY=15
MAX_CACHE=15


# Various constants
HOME_DIR=`pwd`
PROXY_DIR="./.proxy"
NOPROXY_DIR="./.noproxy"
TIMEOUT=0.1 # short enough to make sure it's cached
MAX_RAND=63000
PORT_START=1024
PORT_MAX=65000
MAX_PORT_TRIES=10


# List of text and binary files for the basic test
BASIC_LIST="http://www.example.com/
            http://go.com/
            http://www.washington.edu/
            http://www.internic.com/
            http://eu.httpbin.org/
            http://neverssl.com/
            http://info.cern.ch/
            http://www.softwareqatest.com/
            http://www.vulnweb.com/"


# List of text files for the cache test
CACHE_LIST="http://www.example.com/
            http://www.washington.edu/
            http://www.internic.com/
            http://eu.httpbin.org/
            http://neverssl.com/
            http://info.cern.ch/
            http://www.softwareqatest.com/
            http://www.vulnweb.com/"


# The file we will fetch for various tests
FETCH_FILE="go.html"
FETCH_URL="http://go.com/"

#####
# Helper functions
#

#
# download_proxy - download a file from the origin server via the proxy
# usage: download_proxy <testdir> <filename> <origin_url> <proxy_url>
#
function download_proxy {
    cd $1
    curl --silent --proxy $4 --output $2 $3
    (( $? == 28 )) && echo -e "Error: Fetch timed out after ${TIMEOUT} seconds"
    # cat $2
    cd $HOME_DIR
}

#
# download_proxy_timeout - download a file from the origin server via the proxy
#                           with timeout to test cache
# usage: download_proxy <testdir> <filename> <origin_url> <proxy_url>
#
function download_proxy_timeout {
    cd $1
    curl --max-time ${TIMEOUT} --silent --proxy $4 --output $2 $3
    (( $? == 28 )) && echo -e "Error: Fetch timed out after ${TIMEOUT} seconds"
    # cat $2
    cd $HOME_DIR
}

#
# download_noproxy - download a file directly from the origin server
# usage: download_noproxy <testdir> <filename> <origin_url>
#
function download_noproxy {
    cd $1
    curl --silent --output $2 $3 
    (( $? == 28 )) && echo -e "Error: Fetch timed out after ${TIMEOUT} seconds"
    # cat $2
    cd $HOME_DIR
}

#
# clear_dirs - Clear the download directories
#
function clear_dirs {
    clear_proxy_dir
    clear_noproxy_dir
}

function clear_noproxy_dir {
    rm -rf ${NOPROXY_DIR}/*
}

function clear_proxy_dir {
    rm -rf ${PROXY_DIR}/*
}

#
# wait_for_port_use - Spins until the TCP port number passed as an
#     argument is actually being used. Times out after 5 seconds.
#
function wait_for_port_use() {
    timeout_count="0"
    portsinuse=`netstat --numeric-ports --numeric-hosts -a --protocol=tcpip \
        | grep tcp | cut -c21- | cut -d':' -f2 | cut -d' ' -f1 \
        | grep -E "[0-9]+" | uniq | tr "\n" " "`

    echo -e "${portsinuse}" | grep -wq "${1}"
    while [ "$?" != "0" ]
    do
        timeout_count=`expr ${timeout_count} + 1`
        if [ "${timeout_count}" == "${MAX_PORT_TRIES}" ]; then
            kill -ALRM $$
        fi

        sleep 1
        portsinuse=`netstat --numeric-ports --numeric-hosts -a --protocol=tcpip \
            | grep tcp | cut -c21- | cut -d':' -f2 | cut -d' ' -f1 \
            | grep -E "[0-9]+" | uniq | tr "\n" " "`
        echo -e "${portsinuse}" | grep -wq "${1}"
    done
}


#
# free_port - returns an available unused TCP port 
#
function free_port {
    # Generate a random port in the range [PORT_START,
    # PORT_START+MAX_RAND]. This is needed to avoid collisions when many
    # students are running the driver on the same machine.
    port=$((( RANDOM % ${MAX_RAND}) + ${PORT_START}))

    while [ TRUE ] 
    do
        portsinuse=`netstat --numeric-ports --numeric-hosts -a --protocol=tcpip \
            | grep tcp | cut -c21- | cut -d':' -f2 | cut -d' ' -f1 \
            | grep -E "[0-9]+" | uniq | tr "\n" " "`

        echo -e "${portsinuse}" | grep -wq "${port}"
        if [ "$?" == "0" ]; then
            if [ $port -eq ${PORT_MAX} ]
            then
                echo -e "-1"
                return
            fi
            port=`expr ${port} + 1`
        else
            echo -e "${port}"
            return
        fi
    done
}


#######
# Main 
#######

######
# Verify that we have all of the expected files with the right
# permissions
#

# Kill any stray proxies
killall -q proxy nop-server.py 2> /dev/null

# Make sure we have an existing executable proxy
if [ ! -x ./proxy ]
then 
    echo -e "Error: ./proxy not found or not an executable file. Please rebuild your proxy and try again."
    exit
fi

# Make sure we have an existing executable nop-server.py file
if [ ! -x ./nop-server.py ]
then 
    echo -e "Error: ./nop-server.py not found or not an executable file."
    exit
fi

# Create the test directories if needed
if [ ! -d ${PROXY_DIR} ]
then
    mkdir ${PROXY_DIR}
fi

if [ ! -d ${NOPROXY_DIR} ]
then
    mkdir ${NOPROXY_DIR}
fi

# Add a handler to generate a meaningful timeout message
trap 'echo -e "Timeout waiting for the server to grab the port reserved for it"; kill $$' ALRM


#####
# Basic
#
echo -e "*** Basic ***"

# Run the proxy
proxy_port=$(free_port)
echo -e "Starting proxy on ${proxy_port}"
./proxy ${proxy_port}  &> /dev/null &
proxy_pid=$!

# Wait for the proxy to start in earnest
wait_for_port_use "${proxy_port}"


# Now do the test by fetching some text and binary files directly from
# Tiny and via the proxy, and then comparing the results.
numRun=0
numSucceeded=0
for url in ${BASIC_LIST}
do
    file=$(echo -e $url | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/').html
    numRun=`expr $numRun + 1`
    echo -e "${numRun}: ${file}"
    clear_dirs

    # Fetch using the proxy
    echo -e "   Fetching from \e[1;31m${url}\e[1;0m into ${PROXY_DIR} using the proxy"
    download_proxy $PROXY_DIR ${file} "${url}" "http://localhost:${proxy_port}"

    # Fetch directly from server
    echo -e "   Fetching from \e[1;31m${url}\e[1;0m into ${NOPROXY_DIR} directly from server"
    download_noproxy $NOPROXY_DIR ${file} "${url}"

    # Compare the two files
    echo -e "   Comparing the two files"
    diff -q ${PROXY_DIR}/${file} ${NOPROXY_DIR}/${file} &> /dev/null
    if [ $? -eq 0 ]; then
        numSucceeded=`expr ${numSucceeded} + 1`
        echo -e "   \e[1;32mSuccess\e[1;0m: Files are identical."
    else
        echo -e "   \e[1;31mFailure\e[1;0m: Files differ."
    fi
done


echo -e
echo -e "Killing proxy"
kill $proxy_pid 2> /dev/null
wait $proxy_pid 2> /dev/null

basicScore=`expr ${MAX_BASIC} \* ${numSucceeded} / ${numRun}`

echo -e "basicScore: $basicScore/${MAX_BASIC}"


######
# Concurrency
#

echo -e ""
echo -e "*** Concurrency ***"

# Run the proxy
proxy_port=$(free_port)
echo -e "Starting proxy on port ${proxy_port}"
./proxy ${proxy_port} &> /dev/null &
proxy_pid=$!

# Wait for the proxy to start in earnest
wait_for_port_use "${proxy_port}"

# Run a special blocking nop-server that never responds to requests
nop_port=$(free_port)
echo -e "Starting the blocking NOP server on port ${nop_port}"
python3 ./nop-server.py ${nop_port} &> /dev/null &
nop_pid=$!

# Wait for the nop server to start in earnest
wait_for_port_use "${nop_port}"


# Try to fetch a file from the blocking nop-server using the proxy
clear_dirs
echo -e "Trying to fetch a file from the blocking nop-server"
download_proxy $PROXY_DIR "nop-file.txt" "http://localhost:${nop_port}/nop-file.txt" "http://localhost:${proxy_port}" &

# Fetch directly from server
echo -e "   Fetching from \e[1;31m${FETCH_URL}\e[1;0m into ${NOPROXY_DIR} directly from server"
download_noproxy $NOPROXY_DIR ${FETCH_FILE} "${FETCH_URL}"

# Fetch using the proxy
echo -e "   Fetching from \e[1;31m${FETCH_URL}\e[1;0m  into ${PROXY_DIR} using the proxy"
download_proxy $PROXY_DIR ${FETCH_FILE} "${FETCH_URL}" "http://localhost:${proxy_port}"

# See if the proxy fetch succeeded
echo -e "Checking whether the proxy fetch succeeded"
diff -q ${PROXY_DIR}/${FETCH_FILE} ${NOPROXY_DIR}/${FETCH_FILE} &> /dev/null
if [ $? -eq 0 ]; then
    concurrencyScore=${MAX_CONCURRENCY}
    echo -e "\e[1;32mSuccess\e[1;0m: Was able to fetch tiny/${FETCH_FILE} from the proxy."
else
    concurrencyScore=0
    echo -e "\e[1;31mFailure\e[1;0m: Was not able to fetch tiny/${FETCH_FILE} from the proxy."
fi

# Clean up
echo -e "Killing proxy and nop-server"
kill $proxy_pid 2> /dev/null
wait $proxy_pid 2> /dev/null
kill $nop_pid 2> /dev/null
wait $nop_pid 2> /dev/null

echo -e "concurrencyScore: $concurrencyScore/${MAX_CONCURRENCY}"


#####
# Caching
#
echo -e ""
echo -e "*** Cache ***"


# Run the proxy
proxy_port=$(free_port)
echo -e "Starting proxy on port ${proxy_port}"
./proxy ${proxy_port} &> /dev/null &
proxy_pid=$!

# Wait for the proxy to start in earnest
wait_for_port_use "${proxy_port}"

# Now do the test by fetching some text and binary files directly from
# Tiny and via the proxy, and then comparing the results.
numRun=0
numSucceeded=0
clear_dirs
for url in ${CACHE_LIST}
do
    file=$(echo -e $url | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/').html
    numRun=`expr $numRun + 1`
    echo -e "${numRun}: ${file}"

    # Fetch using the proxy
    echo -e "   Fetching from \e[1;31m${url}\e[1;0m into ${PROXY_DIR} using the proxy"
    download_proxy $PROXY_DIR ${file} "${url}" "http://localhost:${proxy_port}"
done

echo -e
numRun=0
numSucceeded=0
for url in ${CACHE_LIST}
do
    file=$(echo -e $url | sed -e 's/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/').html
    numRun=`expr $numRun + 1`
    echo -e "${numRun}: ${file}"
    clear_noproxy_dir

    # Fetch directly from server
    echo -e "   Fetching a cached copy of ${file} into ${NOPROXY_DIR}"
    download_proxy_timeout $NOPROXY_DIR ${file} "${url}" "http://localhost:${proxy_port}"

    # Compare the two files
    echo -e "   Comparing the two files"
    diff -q ${PROXY_DIR}/${file} ${NOPROXY_DIR}/${file} &> /dev/null
    if [ $? -eq 0 ]; then
        numSucceeded=`expr ${numSucceeded} + 1`
        echo -e "   \e[1;32mSuccess\e[1;0m: Files are identical."
    else
        echo -e "   \e[1;31mFailure\e[1;0m: Files differ."
    fi
done

cacheScore=`expr ${MAX_CACHE} \* ${numSucceeded} / ${numRun}`

# Kill the proxy
echo -e "Killing proxy"
kill $proxy_pid 2> /dev/null
wait $proxy_pid 2> /dev/null

echo -e "cacheScore: $cacheScore/${MAX_CACHE}"

# Emit the total score
totalScore=`expr ${basicScore} + ${cacheScore} + ${concurrencyScore}`
maxScore=`expr ${MAX_BASIC} + ${MAX_CACHE} + ${MAX_CONCURRENCY}`
echo -e ""
echo -e "totalScore: ${totalScore}/${maxScore}"
exit

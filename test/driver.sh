#!/bin/bash
#
# driver.sh - This is a simple autograder for the Proxy Lab. It does
#     basic sanity checks that determine whether or not the code
#     behaves like a concurrent caching proxy. 
#
#     David O'Hallaron, Carnegie Mellon University
#     updated: 2/8/2016
# 
#     usage: ./driver.sh
# 

# Point values
MAX_BASIC=40
MAX_CONCURRENCY=15
MAX_CACHE=15

# Various constants
HOME_DIR=`pwd`
PROXY_DIR="./.proxy"
NOPROXY_DIR="./.noproxy"
TIMEOUT=5
MAX_RAND=63000
PORT_START=1024
PORT_MAX=65000
MAX_PORT_TRIES=10
CACHE_SIZE=`python3 -c "print(1049000/1024)"`

# List of text and binary files for the basic test
BASIC_LIST="home.html
            lib.c
            tiny.c
            godzilla.jpg
            godzilla.gif
            tiny
            1.png
            2.png
            3.png
            4.png
            5.png
            6.png
            7.png
            8.png
            9.png
           10.png
           11.png
           12.png
           13.png
           14.png
           15.png
           16.png"

# List of text files for the cache test
CACHE_LIST="tiny.c
            home.html
            lib.c
            1.png
            2.png
            3.png
            4.png
            5.png
            6.png
            7.png
            8.png
            9.png
           10.png
           11.png
           12.png
           13.png
           14.png
           15.png
           godzilla.jpg
           godzilla.gif"

# The file we will fetch for various tests
FETCH_FILE="home.html"

#####
# Helper functions
#

#
# download_proxy - download a file from the origin server via the proxy
# usage: download_proxy <testdir> <filename> <origin_url> <proxy_url>
#
function download_proxy {
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
    curl --max-time ${TIMEOUT} --silent --output $2 $3 
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

# Kill any stray proxies or tiny servers owned by this user
killall -q proxy tiny test/nop-server.py 2> /dev/null

# Make sure we have a Tiny directory
if [ ! -d ./tiny ]
then 
    echo -e "Error: ./tiny directory not found."
    exit
fi

# If there is no Tiny executable, then try to build it
if [ ! -x ./tiny/tiny ]
then 
    echo -e "Building the tiny executable."
    (cd ./tiny; make)
    echo -e ""
fi

# Make sure we have all the Tiny files we need
if [ ! -x ./tiny/tiny ]
then 
    echo -e "Error: ./tiny/tiny not found or not an executable file."
    exit
fi
for file in ${BASIC_LIST}
do
    if [ ! -e ./tiny/${file} ]
    then
        echo -e "Error: ./tiny/${file} not found."
        exit
    fi
done

# Make sure we have an existing executable proxy
if [ ! -x ./proxy ]
then 
    echo -e "Error: ./proxy not found or not an executable file. Please rebuild your proxy and try again."
    exit
fi

# Make sure we have an existing executable test/nop-server.py file
if [ ! -x ./test/nop-server.py ]
then 
    echo -e "Error: ./test/nop-server.py not found or not an executable file."
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

# Run the Tiny Web server
tiny_port=$(free_port)
echo -e "Starting tiny on ${tiny_port}"
pushd ./tiny &> /dev/null
./tiny ${tiny_port}   &> /dev/null  &
tiny_pid=$!
popd &> /dev/null

# Wait for tiny to start in earnest
wait_for_port_use "${tiny_port}"

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
for file in ${BASIC_LIST}
do
    numRun=`expr $numRun + 1`
    echo -e "${numRun}: ${file}"
    clear_dirs

    # Fetch using the proxy
    echo -e "   Fetching ./tiny/${file} into ${PROXY_DIR} using the proxy"
    download_proxy $PROXY_DIR ${file} "http://localhost:${tiny_port}/${file}" "http://localhost:${proxy_port}"

    # Fetch directly from Tiny
    echo -e "   Fetching ./tiny/${file} into ${NOPROXY_DIR} directly from Tiny"
    download_noproxy $NOPROXY_DIR ${file} "http://localhost:${tiny_port}/${file}"

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

echo -e "Killing tiny and proxy"
kill $tiny_pid 2> /dev/null
wait $tiny_pid 2> /dev/null
kill $proxy_pid 2> /dev/null
wait $proxy_pid 2> /dev/null

basicScore=`expr ${MAX_BASIC} \* ${numSucceeded} / ${numRun}`

echo -e "basicScore: $basicScore/${MAX_BASIC}"


######
# Concurrency
#

echo -e ""
echo -e "*** Concurrency ***"

# Run the Tiny Web server
tiny_port=$(free_port)
echo -e "Starting tiny on port ${tiny_port}"
cd ./tiny
./tiny ${tiny_port} &> /dev/null &
tiny_pid=$!
cd ${HOME_DIR}

# Wait for tiny to start in earnest
wait_for_port_use "${tiny_port}"

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
python3 ./test/nop-server.py ${nop_port} &> /dev/null &
nop_pid=$!

# Wait for the nop server to start in earnest
wait_for_port_use "${nop_port}"

# Try to fetch a file from the blocking nop-server using the proxy
clear_dirs
echo -e "Trying to fetch a file from the blocking nop-server"
download_proxy $PROXY_DIR "nop-file.txt" "http://localhost:${nop_port}/nop-file.txt" "http://localhost:${proxy_port}" &

# Fetch directly from Tiny
echo -e "Fetching ./tiny/${FETCH_FILE} into ${NOPROXY_DIR} directly from Tiny"
download_noproxy $NOPROXY_DIR ${FETCH_FILE} "http://localhost:${tiny_port}/${FETCH_FILE}"

# Fetch using the proxy
echo -e "Fetching ./tiny/${FETCH_FILE} into ${PROXY_DIR} using the proxy"
download_proxy $PROXY_DIR ${FETCH_FILE} "http://localhost:${tiny_port}/${FETCH_FILE}" "http://localhost:${proxy_port}"

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
echo -e "Killing tiny, proxy, and nop-server"
kill $tiny_pid 2> /dev/null
wait $tiny_pid 2> /dev/null
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

# Run the Tiny Web server
tiny_port=$(free_port)
echo -e "Starting tiny on port ${tiny_port}"
cd ./tiny
./tiny ${tiny_port} &> /dev/null &
tiny_pid=$!
cd ${HOME_DIR}

# Wait for tiny to start in earnest
wait_for_port_use "${tiny_port}"

# Run the proxy
proxy_port=$(free_port)
echo -e "Starting proxy on port ${proxy_port}"
./proxy ${proxy_port} &> /dev/null &
proxy_pid=$!

# Wait for the proxy to start in earnest
wait_for_port_use "${proxy_port}"

# Fetch some files from tiny using the proxy
clear_dirs
for file in ${CACHE_LIST}
do
    echo -e "Fetching ./tiny/${file} into ${PROXY_DIR} using the proxy"
    download_proxy $PROXY_DIR ${file} "http://localhost:${tiny_port}/${file}" "http://localhost:${proxy_port}"
done

# Kill Tiny
echo -e "Killing tiny"
kill $tiny_pid 2> /dev/null
wait $tiny_pid 2> /dev/null

numRun=0
numSucceeded=0
accumulatedSize=0
fileSize=0
echo -e
# Now try to fetch a cached copy of the fetched files.
for file in ${CACHE_LIST}
do
    numRun=`expr $numRun + 1`
    echo -e "${numRun}: ${file}"
    clear_noproxy_dir

    echo -e "Fetching a cached copy of ${file} into ${NOPROXY_DIR}"
    download_proxy $NOPROXY_DIR ${file} "http://localhost:${tiny_port}/${file}" "http://localhost:${proxy_port}"
    # See if the proxy fetch succeeded by comparing it with the original
    # file in the tiny directory
    diff -q ./tiny/${file} ${NOPROXY_DIR}/${file}  &> /dev/null
    if [ $? -eq 0 ]; then
        fileSize=`expr $(ls -l ${NOPROXY_DIR}/${file} | cut -d' ' -f5)`
        accumulatedSize=`python3 -c "print(${accumulatedSize} + ${fileSize})"`
        fileSize=`python3 -c "print(${fileSize}/1024)"`
        numSucceeded=`expr ${numSucceeded} + 1`
        printf  "   File Size: %.2fk\n" "${fileSize}"
        echo -e "   \e[1;32mSuccess\e[1;0m: Files are identical."
    else
        echo -e "   \e[1;31mFailure\e[1;0m: Files differ."
    fi
done

echo
printf "accumulatedSize: %.2fk\n" "`python3 -c "print(${accumulatedSize}/1024)"`"
printf "cacheSize: %.2fk\n" "${CACHE_SIZE}"
echo

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

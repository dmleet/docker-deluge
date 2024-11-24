#!/bin/sh

echo "Starting deluged"
deluged --do-not-daemonize --config /home/deluge/.config/deluge --loglevel=${DELUGE_LOGLEVEL}
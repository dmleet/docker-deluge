#!/bin/sh

echo "Injecting core config"
python3 /opt/deluge/inject_core_config.py

echo "Injecting web config"
python3 /opt/deluge/inject_web_config.py

echo "Starting deluged"
cp -r /opt/deluge/plugins /home/deluge/.config/deluge
deluged --do-not-daemonize --config /home/deluge/.config/deluge --loglevel=${DELUGE_LOGLEVEL} &

echo "Waiting for deluge to start listening on port 58846"
while [[ $(netstat -lnt | awk "\$6 == \"LISTEN\" && \$4 ~ \".58846\"") == "" ]]; do
  sleep 0.1
done

echo "Starting deluge-web"
deluge-web --do-not-daemonize --config /home/deluge/.config/deluge --loglevel=${DELUGE_LOGLEVEL} &
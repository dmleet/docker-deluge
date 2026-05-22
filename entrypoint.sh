#!/bin/sh

echo "Injecting core config"
python3 /opt/deluge/inject_core_config.py

echo "Injecting web config"
python3 /opt/deluge/inject_web_config.py

echo "Syncing bundled plugins into config dir"
mkdir -p /home/deluge/.config/deluge/plugins
cp -r /opt/deluge/plugins/. /home/deluge/.config/deluge/plugins/

pid_deluged=
pid_web=

term() {
  echo "Received termination signal, forwarding to deluge processes"
  [ -n "$pid_web" ]     && kill -TERM "$pid_web"     2>/dev/null
  [ -n "$pid_deluged" ] && kill -TERM "$pid_deluged" 2>/dev/null
}
trap term TERM INT

echo "Starting deluged"
deluged --do-not-daemonize --config /home/deluge/.config/deluge --loglevel=${DELUGE_LOGLEVEL} &
pid_deluged=$!

echo "Waiting for deluge to start listening on port 58846"
while [ -z "$(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".58846"')" ]; do
  sleep 0.1
done

echo "Starting deluge-web"
deluge-web --do-not-daemonize --config /home/deluge/.config/deluge --loglevel=${DELUGE_LOGLEVEL} &
pid_web=$!

# Block until one child exits (or a signal trips the trap).
wait -n
term
wait

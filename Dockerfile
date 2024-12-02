FROM docker.io/emmercm/libtorrent:2.0.10-alpine

RUN echo "Install build requirements" && \
    apk add --no-cache --virtual .build_deps build-base python3-dev libffi-dev openssl-dev zlib-dev jpeg-dev geoip-dev rust cargo curl && \
    echo "Install requirements" && \
    apk add --no-cache py3-pip && \
    python3 -m pip install --upgrade pip --break-system-packages && \
    apk add --no-cache geoip && \
    pip3 install --break-system-packages GeoIP && \
    echo "Install deluge" && \
    pip3 install --break-system-packages deluge==2.1.1 && \
    echo "Clear build deps" && \
    apk del .build_deps

RUN echo "Creating deluge user" && \
    addgroup -g 1000 deluge && \
    adduser -u 1000 -G deluge -s /bin/sh -D deluge

ENV XDG_CONFIG_HOME=/home/deluge/.config

VOLUME [ "/home/deluge/.config/deluge" ]
RUN mkdir -p /home/deluge/.config/deluge && \
    chown -R deluge:deluge /home/deluge && \
    mkdir -p /opt/deluge/plugins && \
    chown -R deluge:deluge /opt/deluge

USER deluge

RUN echo "Download and install plugins" && \
    wget -O /opt/deluge/plugins/ltConfig-2.0.0.egg \
        https://github.com/ratanakvlun/deluge-ltconfig/releases/download/v2.0.0/ltConfig-2.0.0.egg

ENV DELUGE_LOGLEVEL=info

# Download a legacy maxmind geoip database and configure deluge to use it
ENV DELUGE_CONF_CORE_GEOIP_DB_LOCATION /opt/deluge/GeoIP-country.dat
# See : https://www.miyuru.lk/geoiplegacy
RUN wget -O - https://dl.miyuru.lk/geoip/maxmind/country/maxmind4.dat.gz | gunzip -c > /opt/deluge/GeoIP-country.dat

ADD --chown=deluge:deluge inject_core_config.py /opt/deluge/inject_core_config.py
ADD --chown=deluge:deluge inject_web_config.py /opt/deluge/inject_web_config.py
ADD --chown=deluge:deluge entrypoint.sh /opt/deluge/entrypoint.sh
RUN chmod +x /opt/deluge/entrypoint.sh

EXPOSE 8112 58846 58946 58946/udp

ENTRYPOINT [ "/opt/deluge/entrypoint.sh" ]
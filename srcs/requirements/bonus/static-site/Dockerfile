FROM debian:12.15-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        lighttpd \
        wget \
    && rm -rf /var/lib/apt/lists/*

COPY conf/lighttpd.conf /etc/lighttpd/inception.conf
COPY website/ /var/www/static/

USER www-data
EXPOSE 8080
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/inception.conf"]

FROM debian:12.15-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssl \
        proftpd-core \
        proftpd-mod-crypto \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -m 0755 /run/proftpd

COPY tools/entrypoint.sh /usr/local/bin/ftp-entrypoint

RUN chmod 0555 /usr/local/bin/ftp-entrypoint

EXPOSE 2121 21100-21110
ENTRYPOINT ["/usr/local/bin/ftp-entrypoint"]
CMD ["proftpd", "--nodaemon", "--config", "/tmp/proftpd.conf"]

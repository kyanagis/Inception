FROM debian:12.15-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        busybox-static \
        ca-certificates \
        gzip \
        mariadb-client \
        tar \
    && rm -rf /var/lib/apt/lists/*

COPY tools/backup.sh /usr/local/bin/backup-now
COPY tools/entrypoint.sh /usr/local/bin/backup-entrypoint

RUN chmod 0555 /usr/local/bin/backup-now /usr/local/bin/backup-entrypoint

ENTRYPOINT ["/usr/local/bin/backup-entrypoint"]
CMD ["busybox", "crond", "-f", "-l", "2", "-c", "/tmp/crontabs"]

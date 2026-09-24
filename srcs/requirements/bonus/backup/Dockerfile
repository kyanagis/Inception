FROM debian:12.15-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

ARG DEBIAN_SNAPSHOT=20260924T000000Z

RUN printf '%s\n' \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ bookworm main" \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ bookworm-updates main" \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}/ bookworm-security main" \
        > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        busybox-static \
        ca-certificates \
        gzip \
        mariadb-client \
        python3 \
        tar \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY tools/backup.sh /usr/local/bin/backup-now
COPY tools/entrypoint.sh /usr/local/bin/backup-entrypoint
COPY tools/manifest.py /usr/local/bin/backup-manifest
COPY tools/schedule.py /usr/local/bin/backup-schedule

RUN chmod 0555 /usr/local/bin/backup-now /usr/local/bin/backup-entrypoint /usr/local/bin/backup-manifest /usr/local/bin/backup-schedule

ENV TZ=UTC

ENTRYPOINT ["/usr/local/bin/backup-entrypoint"]
CMD ["busybox", "crond", "-f", "-l", "2", "-L", "/dev/stderr", "-c", "/run/crontabs"]

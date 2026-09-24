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

FROM debian:12.15-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gosu \
        redis-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/inception.conf
COPY tools/entrypoint.sh /usr/local/bin/redis-entrypoint
COPY tools/healthcheck.sh /usr/local/bin/redis-healthcheck

RUN chmod 0555 /usr/local/bin/redis-entrypoint /usr/local/bin/redis-healthcheck

EXPOSE 6379
ENTRYPOINT ["/usr/local/bin/redis-entrypoint"]
CMD ["redis-server", "/etc/redis/inception.conf"]

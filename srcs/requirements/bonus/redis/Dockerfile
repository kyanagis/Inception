FROM debian:12.15-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends redis-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/inception.conf

USER redis
EXPOSE 6379
CMD ["redis-server", "/etc/redis/inception.conf"]

FROM debian:12.15-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends redis-server \
    && rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/inception.conf

USER redis
EXPOSE 6379
CMD ["redis-server", "/etc/redis/inception.conf"]

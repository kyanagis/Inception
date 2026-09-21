FROM debian:12.15-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        nginx \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default

COPY conf/nginx.conf.template /etc/nginx/nginx.conf.template
COPY tools/entrypoint.sh /usr/local/bin/nginx-entrypoint

RUN chmod 0555 /usr/local/bin/nginx-entrypoint

EXPOSE 443
ENTRYPOINT ["/usr/local/bin/nginx-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]

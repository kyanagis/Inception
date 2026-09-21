FROM debian:12.15-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

ARG ADMINER_VERSION
ARG ADMINER_SHA256

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        lighttpd \
        php8.2-cgi \
        php8.2-mysql \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o www-data -g www-data -m 0755 /var/www/adminer \
    && curl --fail --location --retry 3 \
        "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}-en.php" \
        -o /var/www/adminer/index.php \
    && echo "${ADMINER_SHA256}  /var/www/adminer/index.php" | sha256sum --check --strict - \
    && chown -R www-data:www-data /var/www/adminer

COPY conf/lighttpd.conf /etc/lighttpd/inception.conf
COPY conf/session.ini /etc/php/8.2/cgi/conf.d/99-inception-session.ini

USER www-data
EXPOSE 8080
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/inception.conf"]

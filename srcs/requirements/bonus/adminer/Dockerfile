FROM debian:12.15-slim

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

USER www-data
EXPOSE 8080
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/inception.conf"]

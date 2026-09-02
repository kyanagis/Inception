FROM debian:12.15-slim

ARG WORDPRESS_VERSION
ARG WORDPRESS_SHA256
ARG WP_CLI_VERSION
ARG WP_CLI_SHA256
ARG REDIS_PLUGIN_VERSION
ARG REDIS_PLUGIN_SHA256

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        mariadb-client \
        netcat-openbsd \
        openssl \
        php8.2-cli \
        php8.2-curl \
        php8.2-fpm \
        php8.2-gd \
        php8.2-intl \
        php8.2-mbstring \
        php8.2-mysql \
        php8.2-opcache \
        php8.2-redis \
        php8.2-xml \
        php8.2-zip \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && curl --fail --location --retry 3 \
        "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz" -o /tmp/wordpress.tar.gz \
    && echo "${WORDPRESS_SHA256}  /tmp/wordpress.tar.gz" | sha256sum --check --strict - \
    && tar --extract --gzip --file=/tmp/wordpress.tar.gz --directory=/usr/src \
    && curl --fail --location --retry 3 \
        "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
        -o /usr/local/bin/wp \
    && echo "${WP_CLI_SHA256}  /usr/local/bin/wp" | sha256sum --check --strict - \
    && chmod 0555 /usr/local/bin/wp \
    && curl --fail --location --retry 3 \
        "https://downloads.wordpress.org/plugin/redis-cache.${REDIS_PLUGIN_VERSION}.zip" \
        -o /tmp/redis-cache.zip \
    && echo "${REDIS_PLUGIN_SHA256}  /tmp/redis-cache.zip" | sha256sum --check --strict - \
    && unzip -q /tmp/redis-cache.zip -d /usr/src/wordpress/wp-content/plugins \
    && chown -R www-data:www-data /usr/src/wordpress \
    && rm -f /tmp/wordpress.tar.gz /tmp/redis-cache.zip

COPY conf/php.ini /etc/php/8.2/fpm/conf.d/99-inception.ini
COPY conf/php-fpm.conf /etc/php/8.2/fpm/php-fpm.conf
COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/entrypoint.sh /usr/local/bin/wordpress-entrypoint

RUN chmod 0555 /usr/local/bin/wordpress-entrypoint \
    && rm -f /etc/php/8.2/fpm/pool.d/www.conf.default

WORKDIR /var/www/html
EXPOSE 9000
ENTRYPOINT ["/usr/local/bin/wordpress-entrypoint"]
CMD ["php-fpm8.2", "--nodaemonize"]

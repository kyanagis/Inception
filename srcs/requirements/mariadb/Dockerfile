FROM debian:12.15-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gosu \
        mariadb-server \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/lib/mysql/* \
    && install -d -o mysql -g mysql -m 0750 /var/lib/mysql /run/mysqld \
    && install -d -o root -g root -m 0555 /usr/share/mariadb-secure-files

COPY conf/server.cnf /etc/mysql/mariadb.conf.d/60-inception.cnf
COPY tools/entrypoint.sh /usr/local/bin/mariadb-entrypoint
COPY tools/prepare-state.sh /usr/local/lib/inception/prepare-state.sh
COPY tools/healthcheck.sh /usr/local/bin/mariadb-healthcheck

RUN chmod 0555 /usr/local/bin/mariadb-entrypoint /usr/local/bin/mariadb-healthcheck

EXPOSE 3306
ENTRYPOINT ["/usr/local/bin/mariadb-entrypoint"]
CMD ["mariadbd"]

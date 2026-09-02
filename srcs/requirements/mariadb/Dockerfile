FROM debian:12.15-slim

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

RUN chmod 0555 /usr/local/bin/mariadb-entrypoint

EXPOSE 3306
ENTRYPOINT ["/usr/local/bin/mariadb-entrypoint"]
CMD ["mariadbd"]

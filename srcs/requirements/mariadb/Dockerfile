FROM alpine:3.20

RUN apk update && apk add --no-cache mariadb mariadb-client

RUN mkdir -p /var/lib/mysql /run/mysqld\
    && chown -R mysql:mysql /var/lib/mysql /run/mysqld

COPY conf/my.cnf etc/my.cnf
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

EXPOSE 3306
ENTRYPOINT [ "init.sh" ]
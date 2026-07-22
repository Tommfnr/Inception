FROM alpine:3.20

RUN apk update && apk add --no-cache mariadb mariadb-client

RUN mkdir -p /var/lib/mysql /run/mysql \ 
    && chown -R mysql:mysql /var/lib/mysql /run/mysql
FROM alpine:3.23

RUN apk update && apk add --no-cache \
    php83 php83-fpm php83-mysqli php83-phar php83-session \
    php83-curl php83-dom php83-mbstring php83-gd php83-xml \
    curl bash

RUN ln -sf /usr/bin/php83 /usr/bin/php

# 128M par defaut : insuffisant pour l'extraction de l'archive par wp-cli
RUN echo "memory_limit = 512M" > /etc/php83/conf.d/99-inception.ini

RUN curl -fS -o /usr/local/bin/wp \
      https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

COPY conf/www.conf /etc/php83/php-fpm.d/www.conf
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

RUN mkdir -p /var/www/html
WORKDIR /var/www/html

EXPOSE 9000
ENTRYPOINT ["init.sh"]
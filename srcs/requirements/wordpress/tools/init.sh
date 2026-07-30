#!/bin/sh
set -e

DB_PASS=$(cat /run/secrets/db_password)
WP_ADMIN_PASS=$(cat /run/secrets/wp_admin_password)
WP_USER_PASS=$(cat /run/secrets/wp_user_password)

cd /var/www/html

i=0
until nc -z mariadb 3306; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
        echo "MariaDB ne répond pas après 60s, abandon." >&2
        exit 1
    fi
    echo "En attente de MariaDB... ($i/30)"
    sleep 2
done
echo "MariaDB est prêt."

if [ ! -f wp-config.php ]; then
    wp core download --allow-root

    wp config create --allow-root \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASS}" \
        --dbhost="mariadb:3306"

    wp core install --allow-root \
        --url="${WP_URL}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_EMAIL}"

    wp user create --allow-root \
        "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author --user_pass="${WP_USER_PASS}"
fi

chown -R nobody:nobody /var/www/html

exec php-fpm83 -F
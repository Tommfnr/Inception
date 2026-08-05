#!/bin/sh
set -e

DB_PASS=$(cat /run/secrets/db_password)
DB_ROOT=$(cat /run/secrets/db_root_password)

if [ ! -d /var/lib/mysql/mysql ]; then
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db
fi

if [ ! -f /var/lib/mysql/.init_done ]; then
    cat > /tmp/init.sql <<EOF
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT}';
FLUSH PRIVILEGES;
EOF

    mysqld --user=mysql --bootstrap < /tmp/init.sql
    rm -f /tmp/init.sql
    touch /var/lib/mysql/.init_done
fi

exec mysqld --user=mysql
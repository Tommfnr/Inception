#!/bin/sh
set -e

DB_PASS=$(cat /run/secrets/db_password)
DB_ROOT=$(cat /run/secrets/db_root_password)


#!/bin/bash
# CI smoke test: run inside the built image.
set -e
modules=$(php -m)
for ext in apcu gd imagick intl "Zend OPcache" pdo_mysql redis uploadprogress xdebug zip; do
    grep -qx "$ext" <<< "$modules" || { echo "Missing PHP extension: $ext"; exit 1; }
done
php -v
composer --version
mailpit version
mariadb --version
apache2ctl -t

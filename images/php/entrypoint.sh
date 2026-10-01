#!/bin/bash
set -e
umask 0002

# Remap www-data to the host user so bind-mounted files keep the right owner.
if [ "${USER_ID}" != "0" ] && [ "$(id -u www-data)" != "${USER_ID}" ]; then
    usermod --non-unique --uid "${USER_ID}" www-data
fi
if [ "${GROUP_ID}" != "0" ] && [ "$(id -g www-data)" != "${GROUP_ID}" ]; then
    groupmod --non-unique --gid "${GROUP_ID}" www-data
fi

# Private/tmp paths are relative to the docroot, as in settings.php.
DRUPAL_WRITABLE_DIRS=(
    "${APACHE_DOCUMENT_ROOT}/${DRUPAL_PRIVATE_PATH}"
    "${APACHE_DOCUMENT_ROOT}/${DRUPAL_TMP_PATH}"
    "${APACHE_DOCUMENT_ROOT}/sites/default/files"
    /home/www-data/.composer
)

if [ -d "${APACHE_DOCUMENT_ROOT}" ]; then
    for dir in "${DRUPAL_WRITABLE_DIRS[@]}"; do
        mkdir -p "$dir"
        # Only touch what is wrong: a recursive chown on a large files/
        # directory is very slow on macOS bind mounts.
        find "$dir" \! -user www-data -exec chown www-data:www-data {} +
    done
fi

# Docker Desktop exposes the forwarded agent socket as root only, while
# Composer and Deployer run as www-data.
if [ -S "${SSH_AUTH_SOCK:-}" ]; then
    chown www-data:www-data "${SSH_AUTH_SOCK}"
fi

exec docker-php-entrypoint "$@"

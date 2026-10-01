# Drupal development image: PHP + Apache (mod_php), every dev setting baked in
# and tunable through environment variables (see README).
ARG PHP_VERSION=8.4
ARG MAILPIT_VERSION=v1.29.6

FROM mlocati/php-extension-installer:2 AS ext-installer
FROM composer:2 AS composer
FROM axllent/mailpit:${MAILPIT_VERSION} AS mailpit

FROM php:${PHP_VERSION}-apache-trixie

LABEL org.opencontainers.image.description="Drupal development runtime (PHP + Apache)"

COPY --from=ext-installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=composer /usr/bin/composer /usr/bin/composer
# Used as sendmail_path: every mail() call lands in Mailpit.
COPY --from=mailpit /mailpit /usr/local/bin/mailpit

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    mariadb-client \
    imagemagick \
    rsync \
    patch \
    unzip \
    zip \
    nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Xdebug is always installed but stays inert while XDEBUG_MODE=off.
RUN install-php-extensions \
    apcu \
    gd \
    imagick \
    intl \
    opcache \
    pdo_mysql \
    redis \
    uploadprogress \
    xdebug \
    zip

# www-data gets its own home: `usermod --uid` (entrypoint) re-owns the whole
# home tree, which must not be /var/www and its bind-mounted project.
RUN mkdir -p /home/www-data/.composer/cache \
    && usermod --home /home/www-data www-data \
    && chown -R www-data:www-data /home/www-data \
    && a2enmod rewrite headers expires \
    && sed -ri 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

COPY conf/php.ini /usr/local/etc/php/conf.d/90-drupal.ini
COPY conf/xdebug.ini /usr/local/etc/php/conf.d/zz-xdebug.ini
COPY conf/apache.conf /etc/apache2/conf-enabled/zz-drupal.conf
COPY conf/settings.docker.php /usr/local/etc/drupal/settings.docker.php
COPY conf/ssh.conf /etc/ssh/ssh_config.d/docker.conf
COPY conf/mariadb-client.cnf /etc/mysql/conf.d/docker-client.cnf
COPY conf/bashrc /etc/profile.d/drupal.sh
COPY --chmod=0755 entrypoint.sh /usr/local/bin/drupal-entrypoint

# The project is bind-mounted with the host UID/GID, so Git would flag every
# repository as "dubious ownership" and break Composer git downloads / patches.
RUN git config --system --add safe.directory '*' \
    && echo '. /etc/profile.d/drupal.sh' >> /etc/bash.bashrc

ENV APACHE_DOCUMENT_ROOT=/var/www/html/web \
    COMPOSER_HOME=/home/www-data/.composer \
    PATH=/var/www/html/vendor/bin:$PATH \
    XDEBUG_MODE=off \
    XDEBUG_START_WITH_REQUEST=trigger \
    MYSQL_HOSTNAME=db \
    MYSQL_PORT=3306 \
    MYSQL_DATABASE=drupal \
    MYSQL_USER=drupal \
    MYSQL_PASSWORD=drupal \
    MYSQL_PREFIX= \
    REDIS_ENABLED=0 \
    REDIS_HOSTNAME=redis \
    REDIS_PORT=6379 \
    SMTP_HOSTNAME=mailpit \
    SMTP_PORT=1025 \
    DRUPAL_PRIVATE_PATH=../storage/private/default \
    DRUPAL_TMP_PATH=../storage/tmp/default \
    DRUPAL_CONFIG_SYNC=../config/sync \
    USER_ID=1000 \
    GROUP_ID=1000

WORKDIR /var/www/html

ENTRYPOINT ["drupal-entrypoint"]
CMD ["apache2-foreground"]

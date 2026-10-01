<?php

/**
 * @file
 * Docker settings, shipped in the image: reads the container environment.
 *
 * Include it at the end of the project's settings.php. The file only exists
 * inside the container, so other environments skip it:
 *
 * @code
 * if (file_exists('/usr/local/etc/drupal/settings.docker.php')) {
 *   include '/usr/local/etc/drupal/settings.docker.php';
 * }
 * @endcode
 */

$databases['default']['default'] = [
  'driver' => 'mysql',
  'host' => getenv('MYSQL_HOSTNAME'),
  'port' => getenv('MYSQL_PORT'),
  'database' => getenv('MYSQL_DATABASE'),
  'username' => getenv('MYSQL_USER'),
  'password' => getenv('MYSQL_PASSWORD'),
  'prefix' => getenv('MYSQL_PREFIX') ?: '',
  'collation' => 'utf8mb4_general_ci',
  'isolation_level' => 'READ COMMITTED',
];

$settings['hash_salt'] = getenv('HASH_SALT');
$settings['trusted_host_patterns'] = array_filter([getenv('TRUSTED_HOST_PATTERNS')]);

$settings['file_private_path'] = getenv('DRUPAL_PRIVATE_PATH');
$settings['file_temp_path'] = getenv('DRUPAL_TMP_PATH');
$settings['config_sync_directory'] = getenv('DRUPAL_CONFIG_SYNC');

// Traefik terminates TLS. Apache publishes no port, so its only peer is
// Traefik: trusting the direct peer means trusting the proxy, not any client.
$settings['reverse_proxy'] = TRUE;
$settings['reverse_proxy_addresses'] = [$_SERVER['REMOTE_ADDR'] ?? '127.0.0.1'];
$settings['reverse_proxy_trusted_headers'] = \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_FOR
  | \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_HOST
  | \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_PORT
  | \Symfony\Component\HttpFoundation\Request::HEADER_X_FORWARDED_PROTO;

// Mail goes to Mailpit: mail() through sendmail_path (php.ini), core Symfony
// mailer (Drupal >= 10.2) through this DSN, and the symfony_mailer contrib
// module through SMTP_TRANSPORT so an imported production transport is never
// used locally.
$config['system.mail']['mailer_dsn'] = [
  'scheme' => 'smtp',
  'host' => getenv('SMTP_HOSTNAME'),
  'port' => (int) getenv('SMTP_PORT'),
];
if (getenv('SMTP_TRANSPORT')) {
  $config['symfony_mailer.settings']['default_transport'] = getenv('SMTP_TRANSPORT');
}

// Redis can only be wired once the redis module is enabled, otherwise
// Drupal bootstrap fails: hence the explicit REDIS_ENABLED switch.
if (getenv('REDIS_ENABLED') === '1' && extension_loaded('redis')) {
  $settings['redis.connection']['interface'] = 'PhpRedis';
  $settings['redis.connection']['host'] = getenv('REDIS_HOSTNAME');
  $settings['redis.connection']['port'] = getenv('REDIS_PORT');
  if (getenv('REDIS_PASSWORD')) {
    $settings['redis.connection']['password'] = getenv('REDIS_PASSWORD');
  }
  $settings['cache']['default'] = 'cache.backend.redis';
  $settings['cache_prefix'] = getenv('COMPOSE_PROJECT_NAME') ?: 'drupal';
  $settings['container_yamls'][] = 'modules/contrib/redis/example.services.yml';
}

$settings['skip_permissions_hardening'] = TRUE;
$config['system.logging']['error_level'] = 'verbose';

# Changelog

Versioning contract (images are pulled per `<major>.<minor>`):

- **patch** (1.2.x): image fixes only, compatible with the project files of the
  same minor — `make pull` is enough.
- **minor** (1.x.0): new features; run `make docker-update` to get the matching
  `drupal.mk` / `base.yml`, existing `.env` keeps working.
- **major** (x.0.0): breaking change; read the upgrade notes below.

## 1.0.0

- PHP + Apache image (mod_php) with Xdebug (off by default), APCu, Redis,
  imagick, uploadprogress, Composer, Mailpit sendmail, MariaDB client.
- Node image for theme builds (arm64-safe optipng).
- Managed `docker/compose/base.yml` (Traefik, MariaDB, Redis, Mailpit,
  Adminer in profile `tools`) and `docker/drupal.mk`.
- `settings.docker.php` shipped in the image.
- No theme/frontend targets in `drupal.mk` (project-specific); `install::` is
  a double-colon rule so projects append their own steps.
- `.env` is passed whole to the `app` and `node` containers (`env_file`).
- Vite port variable: `VITE_SERVER_PORT`; no `logs-drupal` target (dblog vs
  file logging is project-specific).

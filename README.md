# drupal-docker-base

Shared local Drupal stack for every project: **versioned images** on ghcr.io
(all the Docker/PHP configuration lives there) and a **thin project layer**
updated with one command. A fix is made once here, released, and every project
gets it with `make pull` (patch) or `make docker-update` (minor).

## How it fits together

```
docker-base (this repo)                      a Drupal project
├── images/php    ── CI ──► ghcr.io/mathieumaingret/drupal-php:8.4-1.2 ─┐
├── images/node   ── CI ──► ghcr.io/mathieumaingret/drupal-node:22-1.2 ─┤ pulled by
├── project/docker/compose/base.yml ─ install.sh ─► docker/compose/base.yml  (managed)
├── project/docker/drupal.mk        ─ install.sh ─► docker/drupal.mk          (managed)
└── project/templates/*             ─ once ──────► Makefile, .env.example,
                                                   docker/compose/project.yml (project-owned)
```

| File in the project          | Owner       | Updated by                     |
|------------------------------|-------------|--------------------------------|
| `docker/compose/base.yml`    | docker-base | `make docker-update`           |
| `docker/drupal.mk`           | docker-base | `make docker-update`           |
| `Makefile`                   | project     | you (`include docker/drupal.mk` + project targets) |
| `docker/compose/project.yml` | project     | you (extra services/overrides, committed) |
| `docker/compose/local.yml`   | developer   | you (git-ignored)              |
| `.env`                       | developer   | you (`DOCKER_BASE_VERSION` set by the installer) |

## Stack

| Service   | Image                                    | Exposed                                   |
|-----------|------------------------------------------|-------------------------------------------|
| `app`     | `drupal-php:${PHP_VERSION}-<version>` (PHP + Apache) | `https://<project>.dev.localhost` |
| `db`      | `mariadb:${MARIADB_VERSION}`             | `127.0.0.1:<random>` (`make db-port`)     |
| `redis`   | `redis:7-alpine`                         | internal                                  |
| `node`    | `drupal-node:${NODE_VERSION}-<version>`  | `127.0.0.1:${VITE_SERVER_PORT}` (Vite HMR)       |
| `mailpit` | `axllent/mailpit`                        | `https://<project>-mailpit.dev.localhost` |
| `adminer` | `adminer` (profile `tools`)              | `https://<project>-adminer.dev.localhost` |

The `drupal-php` image ships: Xdebug (off by default), APCu, Redis, imagick,
uploadprogress, Composer, Mailpit as `sendmail`, MariaDB client (no TLS),
SSH `accept-new`, host UID/GID remap, and `settings.docker.php`.

## One-time setup of this repo

1. Push to GitHub (public repo `mathieumaingret/drupal-docker-base`), then tag a release:
   `git tag v1.0.0 && git push --tags` — the `images` workflow builds amd64 +
   arm64 natively, smoke-tests and publishes.
2. After the first run, set the `drupal-php` and `drupal-node` packages to
   **Public** (GitHub → Packages → Package settings), so projects pull without
   `docker login`.

## Add it to a project

From the project root (prerequisite: a shared Traefik on the external
`traefik-public` network):

```bash
curl -fsSL https://raw.githubusercontent.com/mathieumaingret/drupal-docker-base/main/install.sh | bash
make init      # creates .env (HASH_SALT, USER_ID, GROUP_ID) then stops: review it
make init      # starts the stack, composer + npm install
```

At the end of `settings.php` (the file only exists in the container, other
environments skip it):

```php
if (file_exists('/usr/local/etc/drupal/settings.docker.php')) {
  include '/usr/local/etc/drupal/settings.docker.php';
}
```

Drupal in a sub-directory (e.g. `site/`, Deployer `sub_directory`): set
`APP_DIR=site`. Private/tmp/config paths: `DRUPAL_PRIVATE_PATH`,
`DRUPAL_TMP_PATH`, `DRUPAL_CONFIG_SYNC` (relative to `web/`).

## Daily use

`make help` lists everything:

```bash
make up / down / logs / shell
make update                # after a git pull: composer install, drush deploy, translations
make drush status          # or make drush c='cr' when the arg is also a target
make composer require drupal/foo
make db-import dump.sql.gz / make db-export
make xdebug-on / xdebug-off
make dep deploy stage=draft
make npm run build         # raw npm from the project root
```

Frontend workflows (theme build, Vite dev server…) differ per project: define
them in the project `Makefile` with `$(EXEC_NODE)`. To add steps to
`make install` (e.g. `npm install`), declare another `install::` rule — it runs
after Composer without overriding it.

## Updating a project

```bash
make pull                  # same minor: patch releases + weekly security rebuilds
make docker-update         # latest release: managed files + DOCKER_BASE_VERSION
make docker-update v=1.3.0 # a given release
git diff && make pull
```

Image tags: `8.4-1.2.3` (immutable), `8.4-1.2` (what projects use: patches and
weekly rebuilds), `8.4-1`, `8.4`. See [CHANGELOG](CHANGELOG.md) for the
versioning contract.

## Releasing a fix

1. Change `images/` or `project/`, add a CHANGELOG entry.
2. `git tag vX.Y.Z && git push --tags`.
3. Patch → projects get it with `make pull`; minor/major → `make docker-update`.

## Xdebug

Off by default. `make xdebug-on` sets `XDEBUG_MODE=debug` with
`start_with_request=trigger`: use the browser extension, or `XDEBUG_SESSION=1`
for Drush. In PhpStorm, create a server named after `COMPOSE_PROJECT_NAME`,
mapping the project (or `APP_DIR`) to `/var/www/html`.

## Mail

Nothing leaves the stack: `mail()` goes through Mailpit's sendmail, core's
Symfony mailer through `mailer_dsn`, and the `symfony_mailer` contrib module
through the transport named by `SMTP_TRANSPORT` (create a `mailpit` SMTP
transport → `mailpit:1025` in the project config, or leave it empty).

## SSH & Deployer

The host SSH agent is forwarded (no private key copied). Docker Desktop:
`/run/host-services/ssh-auth.sock` (default). Linux: set `SSH_AUTH_SOCK_HOST`
to your `$SSH_AUTH_SOCK` path — `make check` refuses to start otherwise.

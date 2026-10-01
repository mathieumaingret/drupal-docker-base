#!/usr/bin/env bash
#
# Installs or updates docker-base in the current project (run from its root).
#
#   curl -fsSL https://raw.githubusercontent.com/mathieumaingret/drupal-docker-base/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/mathieumaingret/drupal-docker-base/main/install.sh | bash -s -- 1.2.0
#
# Managed files (docker/drupal.mk, docker/compose/base.yml) are overwritten;
# templates (Makefile, .env.example, docker/compose/project.yml) are only
# created when missing; .env and project files are never touched beyond
# DOCKER_BASE_VERSION.
#
set -euo pipefail

REPO="${DOCKER_BASE_REPO:-mathieumaingret/drupal-docker-base}"
VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    VERSION=$(git ls-remote --tags --refs --sort=-v:refname "https://github.com/${REPO}.git" 'v*.*.*' \
        | head -n1 | sed 's|.*refs/tags/v||')
fi
if [ -z "$VERSION" ]; then
    echo "No docker-base release found in ${REPO}." >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "https://github.com/${REPO}/archive/refs/tags/v${VERSION}.tar.gz" | tar -xz -C "$tmp" --strip-components=1
src="$tmp/project"

mkdir -p docker/compose
cp "$src/docker/drupal.mk" docker/drupal.mk
cp "$src/docker/compose/base.yml" docker/compose/base.yml
echo "Updated docker/drupal.mk, docker/compose/base.yml"

(cd "$src/templates" && find . -type f | sed 's|^\./||') | while read -r file; do
    if [ ! -e "$file" ]; then
        mkdir -p "$(dirname "$file")"
        cp "$src/templates/$file" "$file"
        echo "Created $file"
    fi
done

touch .gitignore
# Appending to a file without a trailing newline would glue two entries.
if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then
    echo >> .gitignore
fi
while read -r line; do
    grep -qxF "$line" .gitignore || echo "$line" >> .gitignore
done < "$src/gitignore"

# Images are tagged per minor: patch releases and weekly rebuilds come with a pull.
minor="${VERSION%.*}"
for envfile in .env .env.example; do
    [ -f "$envfile" ] || continue
    if grep -q '^DOCKER_BASE_VERSION=' "$envfile"; then
        sed -i.bak "s|^DOCKER_BASE_VERSION=.*|DOCKER_BASE_VERSION=${minor}|" "$envfile" && rm -f "$envfile.bak"
    else
        echo "DOCKER_BASE_VERSION=${minor}" >> "$envfile"
    fi
done
echo "$VERSION" > docker/.docker-base-version

echo "docker-base ${VERSION} installed (images *-${minor})."
echo "Changelog: https://github.com/${REPO}/blob/v${VERSION}/CHANGELOG.md"

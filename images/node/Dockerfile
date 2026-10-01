# Theme build image (Vite, image optimisers).
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-alpine

LABEL org.opencontainers.image.description="Drupal theme build runtime (Node)"

RUN apk add --no-cache \
    autoconf \
    automake \
    libtool \
    build-base \
    nasm \
    zlib-dev \
    libpng-dev \
    giflib-dev

# optipng-bin ships a prebuilt x86-64/glibc binary that cannot run on Alpine
# (musl) / ARM64, so it compiles from source. On ARM the bundled libpng build
# references png_init_filter_functions_neon without compiling the NEON sources,
# breaking the link. Disabling the libpng ARM-NEON optimization lets it build.
ENV CFLAGS="-DPNG_ARM_NEON_OPT=0" \
    CPPFLAGS="-DPNG_ARM_NEON_OPT=0"

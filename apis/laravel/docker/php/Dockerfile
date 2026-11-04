# Imagem do php-fpm da stack Laravel. Referência: .design/laravel-api-base.md.
#
# `base` tem só o PHP, as extensões e o composer: é a imagem do `make laravel-composer`,
# que precisa funcionar mesmo com o composer.lock quebrado. `app` acrescenta o vendor
# e o código, e é o que o php-fpm executa.
FROM php:8.5.12-fpm-alpine AS base

# libpq e fcgi ficam; os pacotes de compilação saem depois de construir as extensões.
RUN apk add --no-cache libpq fcgi \
    && apk add --no-cache --virtual .build-deps $PHPIZE_DEPS postgresql-dev \
    && docker-php-ext-install pdo_pgsql \
    && pecl install redis-6.3.0 \
    && docker-php-ext-enable redis \
    && apk del .build-deps

COPY --from=composer:2.11.1 /usr/bin/composer /usr/bin/composer
COPY docker/php/conf.d/ /usr/local/etc/php/conf.d/
COPY docker/php/php-fpm.d/zz-health.conf /usr/local/etc/php-fpm.d/zz-health.conf

WORKDIR /var/www/html

FROM base AS app

# As dependências antes do código: editar o código não reinstala o vendor.
COPY composer.json composer.lock ./
RUN composer install --no-interaction --no-scripts --no-autoloader --prefer-dist

COPY . .
RUN composer dump-autoload --no-interaction \
    && chown -R www-data:www-data storage bootstrap/cache

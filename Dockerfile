# Unofficial SuiteCRM 8 containers
# Copyright (C) 2022 Tuomas Liinamaa <tlii@iki.fi>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Prepare a base image.
FROM debian:bullseye-slim as base
RUN set -eux; \
    apt update && apt -y upgrade; \
    apt install -y \
        curl \
        git \
        gnupg \
        php-cli \
        php-curl \
        php-intl \
        php-gd \
        php-mbstring \
        php-mysql \
        php-soap \
        php-xml \
        php-zip \
        php-imap \
        php-ldap; \
        mkdir /build;

WORKDIR /build

# Get source and use latest master
RUN git clone https://github.com/salesagility/SuiteCRM-Core.git .; \
    git checkout master; \
    echo "# Change to production environment" > .env.local.php; \
    echo "APP_ENV=prod" >> .env.local.php; 



# Get Composer binary to use in other images
FROM composer:1.9.3 AS composer


# Build composer dependencies
FROM base as build-php

COPY --from=composer /usr/bin/composer /usr/bin/composer

WORKDIR /build

ARG COMPOSER_ALLOW_SUPERUSER 1 

RUN apt install -y unzip; \
    composer install --no-dev; \
    composer dumpautoload;



FROM base as build-js

# Get Yarn and Node repositories and install software
RUN curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian/ stable main" >> /etc/apt/sources.list.d/yarn.list; \
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash -; \
    apt update && apt install -y yarn nodejs;

WORKDIR /build

RUN yarn install; \
    yarn run build:common; \
    yarn run build:core; \
    yarn run build:shell;



FROM base as build-themes

COPY --from=build-php /build /build
COPY --from=composer /usr/bin/composer /usr/bin/composer

WORKDIR /build

RUN composer require scssphp/scssphp; \
    ./vendor/bin/pscss -s compressed ./public/legacy/themes/suite8/css/Dawn/style.scss > ./public/legacy/themes/suite8/css/Dawn/style.css



# Create finalized image to be used 
FROM base as final

RUN mkdir /final

# Copy processed artifacts to final image
COPY --from=build-php /build/vendor /final/vendor
COPY --from=build-js /build/dist /final/dist
COPY --from=build-js /build/node_modules /final/node_modules
COPY --from=build-themes /build/public/legacy/themes/suite8/css/Dawn/style.css /final/public/legacy/themes/suite8/css/Dawn/style.css



# Run final image with php-fpm
FROM php:fpm as serve-php-fpm

RUN apt update && apt -y upgrade; \
    apt-get install -y \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        openssl \
        curl \
    ;\
    docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install curl \
    && docker-php-ext-install intl\
    && docker-php-ext-install json \
    && docker-php-ext-install mbstring \
    && docker-php-ext-install mysqli \
    && docker-php-ext-install pdo_mysql \
    && docker-php-ext-install soap \
    && docker-php-ext-install xml \
    && docker-php-ext-install zip \
    && docker-php-ext-install imap \
    && docker-php-ext-install ldap \
    ; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*;

RUN mkdir /suitecrm && chown www-data:www-data /suitecrm;  \
    usermod -u 101 www-data && groupmod -g 101 www-data; \

VOLUME /suitecrm

COPY --from=final --chown=www-data:www-data /build /usr/src/suitecrm/

COPY docker-entrypoint.sh /docker-entrypoint.sh

WORKDIR /suitecrm

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD [ "php-fpm" ]



# Run final image with apache2 and php
FROM php:apache as serve-php-apache2

RUN apt update && apt -y upgrade; \
    apt-get install -y \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    openssl \
    curl \
    ;\
    docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install curl \
    && docker-php-ext-install intl\
    && docker-php-ext-install json \
    && docker-php-ext-install mbstring \
    && docker-php-ext-install mysqli \
    && docker-php-ext-install pdo_mysql \
    && docker-php-ext-install soap \
    && docker-php-ext-install xml \
    && docker-php-ext-install zip \
    && docker-php-ext-install imap \
    && docker-php-ext-install ldap \
    ; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*;

RUN mkdir /suitecrm && chown www-data:www-data /suitecrm

VOLUME /suitecrm

COPY --from=final --chown=www-data:www-data /build /usr/src/suitecrm/

COPY docker-entrypoint.sh /docker-entrypoint.sh

WORKDIR /suitecrm/public

EXPOSE 80

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD [ "apache2-foreground" ]
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

# Make a base image with php-cli and required modules included. FPM will be installed only to serving fpm image.
FROM debian:bullseye-slim as base
RUN set -eux; \
    apt update && apt -y upgrade; \
    apt install -y \
        curl \
        gnupg \
        php-cli \
        php-curl \
        php-intl \
        php-gd \
        php-mysql \
        php-soap \
        php-xml \
        php-zip \
        php-imap \
        php-ldap;



FROM base as build-prepare

RUN apt -y install git; \
    mkdir /build;

WORKDIR /build

RUN git clone https://github.com/salesagility/SuiteCRM-Core.git .



FROM base as build-php

RUN set -eux; \
    apt install -y \
        composer; \
    mkdir /build;

COPY --from=build-prepare /build /build

WORKDIR /build

RUN composer install; \
    composer dumpautoload;



FROM base as build-js

RUN curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | tee /usr/share/keyrings/yarnkey.gpg; \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" >> /etc/apt/sources.list.d/yarn.list; \
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash -; \
    apt-get install -y nodejs; \
    apt install -y yarn;

COPY --from=build-php /build /build

WORKDIR /build

RUN yarn install; \
    yarn run build:common; \
    yarn run build:core; \
    yarn run build:shell;



FROM base as build-themes

COPY --from=build-js /build /build

WORKDIR /build

RUN ./vendor/bin/pscss -s compressed ./public/legacy/themes/suite8/css/Dawn/style.scss > ./public/legacy/themes/suite8/css/Dawn/style.css



FROM base as cleanup

RUN apt install -y \
        composer; 

COPY --from=build-themes /build /build

WORKDIR /build

RUN set -eux; \
    apt install composer; \
    composer composer clearcache; \
    rm -rf vendor/*; \
    composer composer install --no-dev --prefer-dist --optimize-autoloader; \
    composer dumpautoload;


FROM base as serve

RUN set -eux; \
    apt update && apt -y upgrade; \
    && apt install -y php-fpm \
    php-curl \
    php-intl \
    php-json \
    php-gd \
    php-mbstring \
    php-mysqli \
    php-pdo_mysql \
    php-openssl \
    php-soap \
    php-xml \
    php-zip \
    php-imap \
    php-ldap \
    ; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*;

RUN mkdir /suitecrm && chown www-data:www-data /suitecrm

VOLUME /suitecrm

COPY --from=cleanup --chown=www-data:www-data /build /usr/src/suitecrm/

COPY docker-entrypoint.sh /docker-entrypoint.sh

WORKDIR /suitecrm

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD [ "php-fpm" ]
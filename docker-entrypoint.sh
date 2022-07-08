#!/usr/bin/env bash

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


# Partially derived from Docker Hub's official images; 
# Copyright 2014 Docker, Inc.

set -Eeuo pipefail

([[ -d /suitecrm ]] && cd /suitecrm) || (echo "WARN: SuiteCRM installation directory is missing. It should have been pre-made." && mkdir /suitecrm && cd /suitecrm)

user=www-data
group=www-data

# Test for necessary environment variables and exit if missing crucial ones.
	[[ -z $DATABASE_NAME ]] && (echo "ERROR: you need to set DATABASE_NAME to continue"; exit 5)
	[[ -z $DATABASE_USER ]] && (echo "ERROR: you need to set DATABASE_USER to continue"; exit 5)
	[[ -z $DATABASE_PASSWORD ]] && (echo "ERROR: you need to set DATABASE_PASSWORD to continue"; exit 5)
	[[ -z $DATABASE_SERVER ]] && (echo "ERROR: you need to set DATABASE_SERVER to continue"; exit 5)
	[[ -z $SUITECRM_SITEURL ]] && (echo "ERROR: you need to set SUITECRM_SITEURL to continue"; exit 5)

# Setup correct user; (c) Docker, Inc
	if [[ "$1" == apache2* ]] || [ "$1" = 'php-fpm' ]; then
		uid="$(id -u)"
		gid="$(id -g)"
		if [ "$uid" = '0' ]; then
			case "$1" in
				apache2*)
					user="${APACHE_RUN_USER:-www-data}"
					group="${APACHE_RUN_GROUP:-www-data}"

					# strip off any '#' symbol ('#1000' is valid syntax for Apache)
					pound='#'
					user="${user#$pound}"
					group="${group#$pound}"
					;;
				*) # php-fpm
					user='www-data'
					group='www-data'
					;;
			esac
		else
			user="$uid"
			group="$gid"
		fi
	fi

# Create necessary apache2 config changes to maintain directory similarities
if [[ "$1" == apache2* ]]; then
	sed -i -e "s/www\.example\.com/$SUITECRM_SITEURL/g" -e 's/var\/www\/html/suitecrm\/public/g' -e "s/localhost/$SUITECRM_SITEURL/g" /etc/apache2/sites-enabled/000-default.conf /etc/apache2/sites-available/default-ssl.conf;
	sed -i 's/var\/www/suitecrm\/public/g' /etc/apache2/conf-available/docker-php.conf;
fi

# Test for existing installation and install as necessary; original code by Docker, Inc, edited by TLii
if [ ! -e /suitecrm/public/index.php ] && [ ! -e /suitecrm/VERSION ]; then
	
	# Correct permissions if necessary
	if [ "$uid" = '0' ] && [ "$(stat -c '%u:%g' .)" = '0:0' ]; then
		chown "$user:$group" .
	fi

	echo >&2 "SuiteCRM not found in $PWD - copying now..."
	if [ -n "$(find . -mindepth 1 -maxdepth 1 -not -name wp-content)" ]; then
		echo >&2 "WARNING: $PWD is not empty! (copying anyhow)"
	fi

	sourceTarArgs=(
		--create
		--file -
		--directory /usr/src/suitecrm
		--owner "$user" --group "$group"
	)
	targetTarArgs=(
		--extract
		--file -
	)
	if [ "$uid" != '0' ]; then
		# avoid "tar: .: Cannot utime: Operation not permitted" and "tar: .: Cannot change mode to rwxr-xr-x: Operation not permitted"
		targetTarArgs+=( --no-overwrite-dir )
	fi
	# loop over "pluggable" content in the source, and if it already exists in the destination, skip it
	for contentPath in \
		/usr/src/suitecrm/core/modules \
		/usr/src/suitecrm/extensions \
		/usr/src/suitecrm/public/legacy/modules \
		/usr/src/suitecrm/public/legacy/custom/*/* \
	; do
		contentPath="${contentPath%/}"
		[ -e "$contentPath" ] || continue
		contentPath="${contentPath#/usr/src/wordpress/}"
		if [ -e "$PWD/$contentPath" ]; then
			echo >&2 "WARNING: '$PWD/$contentPath' exists. Not overwriting with container version." #TODO: Make this check if update is in fact newer and patch if possible.
			sourceTarArgs+=( --exclude "./$contentPath" )
		fi
	done
	tar "${sourceTarArgs[@]}" . | tar "${targetTarArgs[@]}"
	echo >&2 "Complete! SuiteCRM has been successfully copied to $PWD"
fi

cd /suitecrm

AU_PROMPT=0
AP_PROMPT=0

# If this is a new installation, proceed with it.
if [[ ! -f /suitecrm/install.lock ]]; then

	# Check permissions before install
	find . -type d -not -perm 2755 -exec chmod 2755 {} \;
	find . -type f -not -perm 0644 -exec chmod 0644 {} \;
	find . ! -user www-data -exec chown www-data:www-data {} \;
	chmod +x bin/console

	# Create random admin credentials if none were supplied
    if [[ -z $ADMIN_USER ]]; then
		AU_PROMPT=1;
		ADMIN_USER=admin_$(echo $RANDOM | md5sum | head -c 4; echo);
	fi
	if 	[[ -z $ADMIN_PASSWORD ]]; then
		AP_PROMPT=1;
		ADMIN_PASSWORD=$(echo $RANDOM | md5sum | head -c 24; echo);
	fi

	# Run installer
    ./bin/console suitecrm:app:install -u "$ADMIN_USER" -p "$ADMIN_PASSWORD" -U "$DATABASE_USER" -P "$DATABASE_PASSWORD" -H "$DATABASE_SERVER" -N "$DATABASE_NAME" -S "$SUITECRM_SITEURL" -d "$DEMO";

	find . -type d -not -perm 2755 -exec chmod 2755 {} \;
	find . -type f -not -perm 0644 -exec chmod 0644 {} \;
	find . ! -user www-data -exec chown www-data:www-data {} \;
	chmod +x bin/console
	touch /suitecrm/install.lock;
fi

    [[ AU_PROMPT -eq 1 ]] && echo "WARNING: You did not include ADMIN_USER as an environment variable. Therefore a randomized admin username has been created." && echo "ADMINISTRATOR USERNAME: $ADMIN_USER";
	[[ AP_PROMPT -eq 1 ]] && echo "WARNING: You did not include ADMIN_PASSWORD as an environment variable. Therefore a randomized admin PASSWORD has been created." &&echo "ADMINISTRATOR PASSWORD: $ADMIN_PASSWORD";

if [ "${1#-}" != "$1" ]; then
	set -- php-fpm "$@"
fi

exec "$@"
ARG  PHP_VERSION=8.1
FROM php:${PHP_VERSION}-apache

# Install composer
COPY --from=composer/composer:latest-bin /composer /usr/bin/composer

# Customize
ARG APP_GH_REF
ENV DEBIAN_FRONTEND=noninteractive

# Update and install required debian packages
RUN set -ex; \
    apt-get update; \
    apt-get upgrade --yes; \
    apt-get install --yes --no-install-recommends git unzip; \
    apt-get install --yes --no-install-recommends libpng-dev libjpeg-dev; \
    apt-get install --yes --no-install-recommends libldap-dev; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Customize apache and php settings
RUN set -ex; \
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    { \
     echo 'RemoteIPHeader X-Real-IP'; \
     echo 'RemoteIPInternalProxy 10.0.0.0/8'; \
     echo 'RemoteIPInternalProxy 172.16.0.0/12'; \
     echo 'RemoteIPInternalProxy 192.168.0.0/16'; \
    } > /etc/apache2/conf-available/remoteip.conf; \
    a2enconf remoteip; \
    a2enmod rewrite; \
    a2enmod headers; \
    a2enmod remoteip; \
    docker-php-ext-configure gd --with-jpeg; \
    docker-php-ext-install mysqli gd ldap; \
    pecl install timezonedb; \
    docker-php-ext-enable timezonedb;

# Get and customize librebooking

USER root
ADD app/ /var/www/html/
RUN set -ex; \
    if [ -f /var/www/html/composer.json ]; then \
        composer install --ignore-platform-req=ext-gd; \
    fi; \
    sed \
        -i /var/www/html/database_schema/create-user.sql \
        -e "s:^DROP USER ':DROP USER IF EXISTS ':g" \
        -e "s:booked_user:schedule_user:g" \
        -e "s:localhost:%:g"; \
    if ! [ -d /var/www/html/tpl_c ]; then \
        mkdir /var/www/html/tpl_c; \
        chown www-data:www-data /var/www/html/tpl_c; \
        chmod 775 /var/www/html/tpl_c; \
    fi  
# Final customization
USER root
RUN set -ex; \
    touch /app.log; \
    chown www-data:www-data /app.log; \
    mkdir /config

# Environment
WORKDIR    /
VOLUME     /config
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD        ["apache2-foreground"]

# Labels
LABEL org.opencontainers.image.title="LibreBooking"
LABEL org.opencontainers.image.description="LibreBooking as a container"
LABEL org.opencontainers.image.url="https://github.com/librebooking/docker"
LABEL org.opencontainers.image.source="https://github.com/librebooking/docker"
LABEL org.opencontainers.image.licenses="GPL-3.0"
LABEL org.opencontainers.image.authors="robin.alexander@netplus.ch"

# Set entrypoint
COPY entrypoint.sh /usr/local/bin/
RUN  chmod +x /usr/local/bin/entrypoint.sh

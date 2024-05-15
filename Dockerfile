FROM php:8.1-apache-bullseye

ENV DOLIBARR_VERSION="19.0.2"
ENV DOLIBARR_INSTALL_AUTO 1
ENV DOLIBARR_PROD 1

ENV DOLIBARR_URL_ROOT 'http://localhost'

ENV WWW_USER_ID 33
ENV WWW_GROUP_ID 33

ENV PHP_INI_DATE_TIMEZONE 'UTC'
ENV PHP_INI_MEMORY_LIMIT 256M
ENV PHP_INI_UPLOAD_MAX_FILESIZE 2M
ENV PHP_INI_POST_MAX_SIZE 8M
ENV PHP_INI_ALLOW_URL_FOPEN 0

RUN sed -i \
  -e 's/^\(ServerSignature On\)$/#\1/g' \
  -e 's/^#\(ServerSignature Off\)$/\1/g' \
  -e 's/^\(ServerTokens\) OS$/\1 Prod/g' \
  /etc/apache2/conf-available/security.conf

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
      libfreetype6-dev \
      libjpeg62-turbo-dev \
      libjpeg62-turbo \
      libpng-dev \
      libpng16-16 \
      libldap2-dev \
      libxml2-dev \
      libzip-dev \
      zlib1g-dev \
      libicu-dev \
      g++ \
      default-mysql-client \
      unzip \
      curl \
      apt-utils \
      msmtp \
      msmtp-mta \
      mailutils \
  && apt-get autoremove -y \
  && rm -rf /var/lib/apt/lists/* \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j$(nproc) calendar intl mysqli pdo_mysql gd soap zip \
  && docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/ \
  && docker-php-ext-install -j$(nproc) ldap \
  && mv ${PHP_INI_DIR}/php.ini-production ${PHP_INI_DIR}/php.ini

# Get Dolibarr
RUN curl -fLSs https://github.com/Dolibarr/dolibarr/archive/${DOLIBARR_VERSION}.tar.gz |\
    tar -C /tmp -xz && \
    cp -r /tmp/dolibarr-${DOLIBARR_VERSION}/htdocs/* /var/www/html/ && \
    ln -s /var/www/html /var/www/htdocs && \
    cp -r /tmp/dolibarr-${DOLIBARR_VERSION}/scripts /var/www/ && \
    rm -rf /tmp/* && \
    mkdir -p /var/www/documents && \
    mkdir -p /var/www/html/custom && \
    chown -R www-data:www-data /var/www

COPY ./entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

CMD ["apache2-foreground"]

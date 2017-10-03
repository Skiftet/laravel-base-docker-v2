FROM php:7.1-fpm-alpine

RUN { \
	echo 'opcache.memory_consumption=128'; \
	echo 'opcache.interned_strings_buffer=8'; \
	echo 'opcache.max_accelerated_files=4000'; \
	echo 'opcache.revalidate_freq=60'; \
	echo 'opcache.fast_shutdown=1'; \
	echo 'opcache.enable_cli=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini

ENV LOCAL_TIMEZONE Europe/Stockholm

RUN echo "http://nl.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories \
    && apk add --no-cache --virtual .build-deps \
        freetype-dev \
        libjpeg-turbo-dev \
        postgresql-dev \
        libpng-dev \
        icu-dev \
        tzdata \
        tidyhtml-dev \
    && apk add --no-cache --virtual .required-deps \
        nginx \
        supervisor \
        bash \
        sed \
        dumb-init \
        freetype \
        libjpeg-turbo \
        postgresql-libs \
        libpng \
        icu-libs \
        tidyhtml-libs \
    && docker-php-ext-configure gd \
        --with-gd \
        --with-freetype-dir=/usr/include/ \
        --with-png-dir=/usr/include/ \
        --with-jpeg-dir=/usr/include/ \
    && NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
    && docker-php-ext-install -j${NPROC} \
        gd \
        mysqli \
        opcache \
        pdo_pgsql \
        intl \
        pdo_mysql \
        tidy \
        pcntl \
    && cp /usr/share/zoneinfo/$LOCAL_TIMEZONE /etc/localtime \
    && echo $LOCAL_TIMEZONE > /etc/timezone \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/*

RUN ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
		&& chown -R www-data:www-data /var/lib/nginx

ENV NR_AGENT_VERSION 6.8.0.177
ENV NR_INSTALL_SILENT 1
ENV NR_INSTALL_PHPLIST /usr/local/bin
RUN mkdir -p /srv \
    && curl https://download.newrelic.com/php_agent/archive/$NR_AGENT_VERSION/newrelic-php5-$NR_AGENT_VERSION-linux-musl.tar.gz | tar xz -C /srv \
    && /srv/newrelic-php5-$NR_AGENT_VERSION-linux-musl/newrelic-install install

VOLUME /srv/storage/main

ENV COMPOSER_ALLOW_SUPERUSER 1
ENV COMPOSER_VERSION 1.4.2
ENV COMPOSER_SHA1 4400106431775fc9fc45acfb875b6e34ab3fea62

ONBUILD COPY ./ /srv/app
ONBUILD RUN rm -rf /srv/app/storage \
    && ln -s /srv/storage/main /srv/app/storage \
    && mkdir -p /srv/storage/main/framework/cache /srv/storage/main/framework/sessions /srv/storage/main/framework/views \
    && curl -o composer.phar https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar \
    && echo "$COMPOSER_SHA1 *composer.phar" | sha1sum -c - \
    && php composer.phar global require "hirak/prestissimo:^0.3" \
    && php composer.phar install -d /srv/app --no-dev \
    && rm composer.phar \
    && rm -rf ~/.composer \
    && chown -R www-data:www-data /srv/app

COPY run.sh /srv/run.sh
RUN chmod +x /srv/run.sh
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY php-fpm.conf /usr/local/etc/php-fpm.d/zz-skiftet.conf
COPY nginx.conf /etc/nginx/nginx.conf
COPY fastcgi_params /etc/nginx/fastcgi_params

WORKDIR /srv/app

# For nginx
EXPOSE 80

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/srv/run.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]

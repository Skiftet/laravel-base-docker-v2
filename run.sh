#!/bin/bash
set -e

echo "Enabling APM metrics for ${NR_APP_NAME}"
/srv/newrelic-php5-$NR_AGENT_VERSION-linux-musl/newrelic-install install

# Update the application name
sed -i "s/newrelic.appname = \"PHP Application\"/newrelic.appname = \"${NR_APP_NAME}\"/" /usr/local/etc/php/conf.d/newrelic.ini

mkdir -p /srv/storage/main/logs /srv/storage/main/app/public /srv/storage/main/framework/cache /srv/storage/main/framework/sessions /srv/storage/main/framework/views
# ln -sf /dev/stderr /srv/storage/main/logs/laravel.log

chown -R www-data:www-data /srv/storage/main

php -- "$DB_CONNECTION" "$DB_HOST" "$DB_PORT" "$DB_DATABASE" "$DB_USERNAME" "$DB_PASSWORD" <<'EOPHP'
<?php

switch (trim($argv[1])) {
    case '':
        echo 'Ingen databas vald';
        exit(0);
    case 'sqlite':
        echo 'Sqlite vald som databas';
        exit(0);
}

$stderr = fopen('php://stderr', 'w');
for ($maxTries = 10;;) {
    try {
        $pdo = new PDO("$argv[1]:host=$argv[2];port=$argv[3];dbname=$argv[4]", $argv[5], $argv[6]);
        echo 'Anslutning till databas lyckades.', "\n";
        break;
    } catch (PDOException $e) {
        --$maxTries;
        if ($maxTries <= 0) {
            fwrite($stderr, 'Anslutning till databas misslyckades.'."\n");
            exit(1);
        }
        fwrite($stderr, 'Anslutning till databas misslyckades. Försöker igen...'."\n");
        sleep(2);
	}
}
EOPHP

exec "$@"

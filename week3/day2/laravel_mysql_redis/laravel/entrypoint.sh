#!/bin/sh
set -e

cd /var/www

cat > .env << EOF
APP_NAME=Laravel
APP_ENV=${APP_ENV:-production}
APP_KEY=
APP_DEBUG=${APP_DEBUG:-false}
APP_URL=${APP_URL:-http://localhost}

DB_CONNECTION=mysql
DB_HOST=${DB_HOST:-mysql}
DB_PORT=3306
DB_DATABASE=${DB_DATABASE:-laravel}
DB_USERNAME=${DB_USERNAME:-laravel}
DB_PASSWORD=${DB_PASSWORD:-secret}

CACHE_STORE=${CACHE_STORE:-redis}
SESSION_DRIVER=${SESSION_DRIVER:-redis}
QUEUE_CONNECTION=${QUEUE_CONNECTION:-redis}

REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=6379
EOF

php artisan key:generate --force --quiet

echo "Waiting for MySQL..."
until php -r "new PDO('mysql:host=${DB_HOST:-mysql};dbname=${DB_DATABASE:-laravel}', '${DB_USERNAME:-laravel}', '${DB_PASSWORD:-secret}');" 2>/dev/null; do
    sleep 2
done
echo "MySQL ready."

# run migrations only for the main app process, not queue workers
if [ "$1" = "php-fpm" ]; then
    php artisan migrate --force --quiet
    php artisan config:cache --quiet
    php artisan route:cache --quiet
fi

exec "$@"

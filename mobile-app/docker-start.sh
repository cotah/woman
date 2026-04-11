#!/bin/sh
set -e

# Use Railway's PORT or default to 80
PORT="${PORT:-80}"

# Generate nginx config at runtime so $PORT is resolved
cat > /etc/nginx/conf.d/default.conf << ENDOFCONF
server {
    listen ${PORT};
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
ENDOFCONF

echo "Starting nginx on port ${PORT}"
exec nginx -g 'daemon off;'

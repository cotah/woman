# ── Stage 1: Build Flutter Web ───────────────────
FROM instrumentisto/flutter:3 AS build

WORKDIR /app

ARG MAPBOX_TOKEN=""
ARG ENVIRONMENT=staging

COPY . ./

RUN flutter pub get
RUN flutter build web --release \
    --dart-define=ENVIRONMENT=$ENVIRONMENT \
    --dart-define=MAPBOX_TOKEN=$MAPBOX_TOKEN

# ── Stage 2: Serve with nginx ───────────────────
FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html

# Write nginx config template (PORT is substituted at runtime by envsubst)
RUN mkdir -p /etc/nginx/templates && \
    cat > /etc/nginx/templates/default.conf.template << 'ENDCONF'
server {
    listen ${PORT};
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types application/javascript application/wasm application/json text/css text/plain;
    gzip_min_length 256;

    # Never cache index.html and service worker (always get latest deploy)
    location ~ ^/(index\.html|flutter_service_worker\.js|version\.json)$ {
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
    }

    # Never cache main.dart.js (Flutter doesn't hash the filename)
    location = /main.dart.js {
        add_header Cache-Control "no-cache, must-revalidate";
    }

    # Cache assets with hashed filenames (fonts, images, etc.)
    location /assets/ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    # SPA fallback
    location / {
        try_files $uri $uri/ /index.html;
    }
}
ENDCONF

# Remove default config (template will generate it)
RUN rm -f /etc/nginx/conf.d/default.conf

ENV PORT=80

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

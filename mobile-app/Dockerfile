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
RUN cat > /etc/nginx/templates/default.conf.template << 'ENDCONF'
server {
    listen ${PORT};
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types application/javascript application/wasm application/json text/css text/plain;
    gzip_min_length 256;

    location ~* \.(js|css|wasm|png|jpg|ico|json)$ {
        expires 1h;
        add_header Cache-Control "public, immutable";
    }

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

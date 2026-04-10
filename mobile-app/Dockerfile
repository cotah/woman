# ── Stage 1: Build Flutter Web ───────────────────
FROM instrumentisto/flutter:3 AS build

WORKDIR /app

ARG MAPBOX_TOKEN=""

COPY . ./

RUN flutter pub get
RUN flutter build web --release --dart-define=MAPBOX_TOKEN=$MAPBOX_TOKEN

# ── Stage 2: Serve with nginx ───────────────────
FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html

# Add WASM MIME type to the default mime.types and write nginx config
RUN echo 'application/wasm wasm;' >> /etc/nginx/mime.types && \
    cat > /etc/nginx/conf.d/default.conf << 'ENDCONF'
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    # Gzip — critical for CanvasKit WASM (6.8MB -> ~2MB)
    gzip on;
    gzip_types application/javascript application/wasm application/json text/css text/html text/plain;
    gzip_min_length 256;

    # Cache static assets
    location ~* \.(js|css|wasm|png|jpg|ico|json)$ {
        expires 1h;
        add_header Cache-Control "public, immutable";
    }

    # SPA fallback
    location / {
        try_files $uri $uri/ /index.html;
    }
}
ENDCONF

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

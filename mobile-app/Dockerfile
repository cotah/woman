# ── Stage 1: Build Flutter Web ───────────────────
FROM instrumentisto/flutter:3 AS build

WORKDIR /app

# Mapbox token passed as build argument
ARG MAPBOX_TOKEN=""

COPY . ./

RUN flutter pub get
RUN flutter build web --release --dart-define=MAPBOX_TOKEN=$MAPBOX_TOKEN

# ── Stage 2: Serve with nginx ───────────────────
FROM nginx:alpine

# Copy built web app
COPY --from=build /app/build/web /usr/share/nginx/html

# Custom nginx config for SPA routing
RUN echo 'server { \
    listen 80; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD 
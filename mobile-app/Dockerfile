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

# SPA routing — all paths serve index.html
RUN echo 'server { \
    listen 80; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

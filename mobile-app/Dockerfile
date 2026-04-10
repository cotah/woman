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

# Write nginx config with placeholder port
RUN echo 'server { listen PORT_PLACEHOLDER; root /usr/share/nginx/html; index index.html; location / { try_files $uri $uri/ /index.html; } }' > /etc/nginx/conf.d/default.conf

EXPOSE 80

# Replace placeholder with actual PORT at runtime, then start nginx
CMD sh -c "sed -i s/PORT_PLACEHOLDER/\${PORT:-80}/ /etc/nginx/conf.d/default.conf && exec nginx -g 'daemon off;'"

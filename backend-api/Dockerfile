# ── Stage 1: Build ───────────────────────────────
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . ./

# Build NestJS app
RUN npm run build
# Verify the build worked
RUN ls dist/main.js

# ── Stage 2: Production ─────────────────────────
FROM node:20-alpine

WORKDIR /app

COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
COPY --from=build /app/tsconfig.json ./
COPY --from=build /app/tsconfig.build.json ./

EXPOSE 3000

CMD ["node", "-r", "tsconfig-paths/register", "dist/main"]

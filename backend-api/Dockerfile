# ── Stage 1: Install ALL dependencies (including dev) ──
FROM node:20-alpine AS deps

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

# ── Stage 2: Build ───────────────────────────────
FROM node:20-alpine AS build

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . ./

# Build the NestJS app (needs @nestjs/cli from devDependencies)
RUN npm run build && ls -la dist/

# ── Stage 3: Production (only prod dependencies) ─
FROM node:20-alpine AS production

WORKDIR /app

ENV NODE_ENV=production

RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup

# Install only production dependencies
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Copy built app
COPY --from=build /app/dist ./dist
COPY --from=build /app/src/database/migrations ./migrations

USER appuser

EXPOSE 3000

CMD ["node", "dist/main"]

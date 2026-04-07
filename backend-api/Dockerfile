# ── Stage 1: Install ALL dependencies ────────────
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . ./

# Build NestJS app
RUN npm run build

# Verify build output exists
RUN ls -la dist/main.js || (echo "BUILD FAILED - dist/main.js not found" && exit 1)

# ── Stage 2: Production ─────────────────────────
FROM node:20-alpine

WORKDIR /app

# Copy everything needed to run (including tsconfig for path aliases)
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
COPY --from=build /app/tsconfig.json ./

EXPOSE 3000

# Use tsconfig-paths to resolve @/* path aliases at runtime
CMD ["node", "-r", "tsconfig-paths/register", "dist/main"]

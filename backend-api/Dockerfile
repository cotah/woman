# ── Stage 1: Install ALL dependencies ────────────
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . ./

# Show TypeScript errors explicitly, then build
RUN npx tsc --noEmit 2>&1 || true
RUN echo "--- Building with nest ---"
RUN npm run build 2>&1; echo "Build exit code: $?"
RUN echo "--- Contents of dist/ ---" && ls -la dist/ 2>/dev/null || echo "dist/ does not exist"
RUN ls -la dist/main.js || (echo "BUILD FAILED" && exit 1)

# ── Stage 2: Production ─────────────────────────
FROM node:20-alpine

WORKDIR /app

COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
COPY --from=build /app/tsconfig.json ./

EXPOSE 3000

CMD ["node", "-r", "tsconfig-paths/register", "dist/main"]

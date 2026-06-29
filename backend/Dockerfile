# IGRIS Backend — Production Dockerfile

# ── Base image ────────────────────────────────────────────────────────
FROM node:20-alpine

# ── Build tools for native modules (sharp, sqlite3, bcrypt, etc.) ────
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    libc6-compat \
    vips-dev

# ── Working directory ─────────────────────────────────────────────────
WORKDIR /app

# ── Install dependencies FIRST (cached layer if package.json unchanged)
COPY package*.json ./
RUN npm install --omit=dev --legacy-peer-deps

# ── Copy application source ────────────────────────────────────────────
COPY . .

# ── Create least-privilege user ────────────────────────────────────────
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup && \
    mkdir -p /app/logs /app/uploads && \
    chown -R appuser:appgroup /app/src /app/package*.json /app/.env /app/logs /app/uploads 2>/dev/null || true

USER appuser

# ── Runtime settings ───────────────────────────────────────────────────
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8080/health || exit 1

CMD ["node", "src/server.js"]
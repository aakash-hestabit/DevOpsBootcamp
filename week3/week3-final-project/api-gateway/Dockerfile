FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev

FROM node:20-alpine
RUN apk add --no-cache curl
RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -D appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --chown=appuser:appgroup . .
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:3000/health || exit 1
CMD ["node", "src/index.js"]

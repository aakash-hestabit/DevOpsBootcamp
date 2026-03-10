FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:1.25-alpine
RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -D appuser
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/build /usr/share/nginx/html
RUN mkdir -p /etc/nginx/ssl \
    && chown -R appuser:appgroup /usr/share/nginx/html /var/cache/nginx /var/log/nginx /etc/nginx/conf.d /etc/nginx/ssl \
    && touch /var/run/nginx.pid && chown appuser:appgroup /var/run/nginx.pid
USER appuser
EXPOSE 80 443
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-check-certificate -qO- https://127.0.0.1:443/ || exit 1
CMD ["nginx", "-g", "daemon off;"]

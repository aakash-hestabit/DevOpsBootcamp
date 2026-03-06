FROM node:20-alpine

RUN apk add --no-cache curl

WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY index.js .

EXPOSE 3000

HEALTHCHECK --interval=20s --timeout=5s --retries=3 --start-period=20s \
  CMD curl -sf http://localhost:${APP_PORT:-3000}/health || exit 1

CMD ["node", "index.js"]

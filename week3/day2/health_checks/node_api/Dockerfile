FROM node:20-alpine

RUN apk add --no-cache curl

WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY index.js .
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /healthcheck.sh

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=30s \
  CMD ["/healthcheck.sh"]

CMD ["node", "index.js"]

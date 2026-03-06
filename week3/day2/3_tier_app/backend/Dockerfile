FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm install 

FROM node:20-alpine

RUN apk add --no-cache curl

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY . .

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

RUN chown -R appuser:appgroup /app
USER appuser

EXPOSE 3000


CMD ["node", "index.js"]

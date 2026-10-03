FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY server ./server
COPY public ./public
ENV PORT=3000 HOST=0.0.0.0 TZ=Africa/Cairo
RUN apk add --no-cache tzdata && mkdir -p /app/data
VOLUME ["/app/data"]
EXPOSE 3000
CMD ["node", "--disable-warning=ExperimentalWarning", "server/index.js"]

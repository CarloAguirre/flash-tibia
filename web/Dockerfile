FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
COPY public ./public
ENV PORT=8080 WEB_ROOT=/app/public
EXPOSE 8080
CMD ["node", "server.js"]

FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
ENV TFS_HOST=tfs TFS_LOGIN=7171 TFS_GAME=7172 HEALTH_PORT=7979
EXPOSE 7171 7172 7979
CMD ["node", "server.js"]

FROM node:22-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY kb ./kb
COPY kb.js ./
COPY recommender.js ./
COPY scripts ./scripts
COPY server.js ./
ENV PORT=8095 AI_GATEWAY_MODE=mock GEMINI_ENABLED=false MAX_BODY_BYTES=32768 MAX_TEXT_BYTES=240
EXPOSE 8095
CMD ["node", "server.js"]
FROM node:22-alpine

WORKDIR /app

# Install dependencies first for Docker layer caching
COPY package*.json ./
RUN npm ci --omit=dev

# Copy application source code
COPY app.js ./
COPY server ./server

# Prepare binary storage directory
RUN mkdir -p /app/.binary && chmod 700 /app/.binary

EXPOSE 8080

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8080
ENV BINARY_STORAGE_ROOT=/app/.binary

CMD ["npm", "start"]

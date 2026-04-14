# syntax=docker/dockerfile:1.6
FROM node:20-alpine

WORKDIR /app

# No runtime deps yet; copy lockfile + manifest first to keep the layer cacheable
# once dependencies are added.
COPY package.json package-lock.json ./
RUN npm install --omit=dev

COPY server.js ./

ENV NODE_ENV=production
ENV PORT=3000
EXPOSE 3000

USER node
CMD ["node", "server.js"]

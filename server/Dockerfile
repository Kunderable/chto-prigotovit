FROM node:20-alpine
WORKDIR /app
COPY package.json products.json ./
COPY src ./src
USER node
EXPOSE 8080
CMD ["node", "src/server.mjs"]

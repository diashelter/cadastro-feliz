# Frontend em modo de desenvolvimento. Referência: .design/frontend-container.md.
# O código entra por cópia; `make watch-frontend` sincroniza as edições.
FROM node:26.13.0-alpine

ENV NEXT_TELEMETRY_DISABLED=1

WORKDIR /app
# O Compose Watch grava em /app como o usuário do container.
RUN chown node:node /app
USER node

COPY --chown=node:node package.json package-lock.json .npmrc ./
RUN npm ci

COPY --chown=node:node . .

EXPOSE 3000
CMD ["node_modules/.bin/next", "dev", "--hostname", "0.0.0.0", "--port", "3000"]

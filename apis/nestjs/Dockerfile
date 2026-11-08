# Stack NestJS em modo de desenvolvimento. Referência: .design/nestjs-stack.md.
# O código entra por cópia; `make watch-nest` sincroniza as edições, e o modo watch do
# Nest CLI recompila e reinicia o processo.
FROM node:26.13.0-alpine AS base

WORKDIR /app
# O Compose Watch grava em /app como o usuário do container.
RUN chown node:node /app
USER node

# A imagem da api e do worker: dependências instaladas pelo lock, e o código por cópia.
FROM base AS app

COPY --chown=node:node package.json package-lock.json .npmrc ./
RUN npm ci

COPY --chown=node:node . .

EXPOSE 8080
CMD ["node_modules/.bin/nest", "start", "--watch", "--preserveWatchOutput"]

import type { ConnectionOptions } from 'bullmq';
import { env } from './config';

// As filas do redis da stack, só no worker (Key decision 1 de .design/nestjs-stack.md).

export const RELAY_QUEUE = 'outbox-relay';
export const RELAY_SCHEDULER = 'outbox-relay';
export const RELAY_EVERY_MS = 1000;
export const EMAIL_QUEUE = 'registration-emails';

/** As conexões que consomem e agendam esperam o Redis voltar, tentando de novo a cada segundo. */
export function waitingConnection(): ConnectionOptions {
  return { ...env.queue(), maxRetriesPerRequest: null, retryStrategy: () => 1000 };
}

/**
 * A conexão por onde o relay publica desiste em 1 s por comando, sem retentar e sem fila
 * offline: uma fila travada não segura o lote aberto (door 5 do plano).
 */
export function publishingConnection(): ConnectionOptions {
  return {
    ...env.queue(),
    connectTimeout: 1000,
    commandTimeout: 1000,
    maxRetriesPerRequest: 0,
    enableOfflineQueue: false,
    retryStrategy: () => 1000,
  };
}

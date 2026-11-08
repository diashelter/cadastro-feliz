// As variáveis de ambiente da stack, lidas quando um módulo as pede: os testes unitários
// importam as regras sem precisar delas. Referência: docs/infrastructure.md › Variáveis.

function read(name: string): string {
  const value = process.env[name];
  if (value === undefined || value === '') {
    throw new Error(`missing environment variable ${name}`);
  }
  return value;
}

function int(name: string): number {
  const value = Number.parseInt(read(name), 10);
  if (!Number.isFinite(value)) {
    throw new Error(`environment variable ${name} is not an integer`);
  }
  return value;
}

export const env = {
  corsAllowedOrigin: () => read('CORS_ALLOWED_ORIGIN'),
  database: () => ({
    host: read('DB_HOST'),
    port: int('DB_PORT'),
    database: read('DB_DATABASE'),
    username: read('DB_USERNAME'),
    password: read('DB_PASSWORD'),
  }),
  limiter: () => ({ host: read('LIMITER_REDIS_HOST'), port: int('LIMITER_REDIS_PORT') }),
  queue: () => ({ host: read('REDIS_HOST'), port: int('REDIS_PORT') }),
  smtp: () => ({ host: read('SMTP_HOST'), port: int('SMTP_PORT'), from: read('MAIL_FROM') }),
  registration: () => ({
    maxAttempts: int('REGISTRATION_MAX_ATTEMPTS'),
    attemptWindow: int('REGISTRATION_ATTEMPT_WINDOW_SECONDS'),
    maxPerIp: int('REGISTRATION_MAX_PER_IP'),
    ipWindow: int('REGISTRATION_IP_WINDOW_SECONDS'),
  }),
  outbox: () => ({
    batchSize: int('OUTBOX_BATCH_SIZE'),
    republishAfter: int('OUTBOX_REPUBLISH_AFTER_SECONDS'),
    maxAttempts: int('OUTBOX_MAX_ATTEMPTS'),
    backoffBase: int('OUTBOX_BACKOFF_BASE_SECONDS'),
  }),
};

/** Rejeita a promessa que não termina em `ms`, para nenhuma espera segurar uma requisição ou um lote. */
export function withTimeout<T>(promise: Promise<T>, ms: number, what: string): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${what} timed out after ${ms} ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

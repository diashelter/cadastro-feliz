import type { CorsOptions } from '@nestjs/common/interfaces/external/cors-options.interface';
import type { Request } from 'express';

/**
 * CORS só em /users, para a origem de CORS_ALLOWED_ORIGIN (docs/api-contract.md). A origem vai
 * numa lista: com uma origem só, como texto, a biblioteca a devolveria a qualquer pedido.
 */
export function corsFor(allowedOrigin: string) {
  const users: CorsOptions = {
    origin: [allowedOrigin],
    methods: ['POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type'],
    exposedHeaders: ['Retry-After'],
    optionsSuccessStatus: 204,
  };
  return (req: Request, callback: (error: Error | null, options: CorsOptions) => void): void => {
    const path = req.path ?? req.url;
    callback(null, path === '/users' ? users : { origin: false });
  };
}

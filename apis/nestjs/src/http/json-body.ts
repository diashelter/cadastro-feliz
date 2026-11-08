import type { NextFunction, Request, Response } from 'express';

const LIMIT_BYTES = 1024 * 1024;

/**
 * Lê o corpo JSON no lugar do parser do Nest, que responde 400. Um corpo malformado, grande
 * demais ou que não é um objeto vira `{}`, e a validação responde o 422 do contrato com os
 * dois campos ausentes (docs/api-contract.md › 422).
 */
export function readJsonBody(req: Request, _res: Response, next: NextFunction): void {
  if (req.method !== 'POST') {
    next();
    return;
  }
  const chunks: Buffer[] = [];
  let size = 0;
  let tooLarge = false;
  req.on('data', (chunk: Buffer) => {
    size += chunk.length;
    if (size > LIMIT_BYTES) {
      tooLarge = true;
      return;
    }
    chunks.push(chunk);
  });
  req.on('end', () => {
    req.body = tooLarge ? {} : parseObject(Buffer.concat(chunks).toString('utf8'));
    next();
  });
  req.on('error', () => {
    req.body = {};
    next();
  });
}

export function parseObject(text: string): Record<string, unknown> {
  try {
    const value: unknown = JSON.parse(text);
    return value !== null && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

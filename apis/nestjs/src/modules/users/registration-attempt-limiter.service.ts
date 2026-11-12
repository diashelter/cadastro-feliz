import { Inject, Injectable } from '@nestjs/common';
import Redis from 'ioredis';
import { env } from '../../config';
import { attemptsKey, quotaKey } from './registration-keys';

export const LIMITER_REDIS = Symbol('LIMITER_REDIS');

/** O par IP e e-mail ou a cota do IP passou do limite; `retryAfter` vai no header `Retry-After`. */
export class RegistrationLimited extends Error {
  constructor(readonly retryAfter: number) {
    super('registration limited');
  }
}

/**
 * O contador de tentativas e a cota por IP no redis-limiter, com comandos do ioredis. O formato
 * das chaves é desta stack (decisão 28).
 *
 * Cada operação incrementa e compara o valor devolvido: verificar antes e incrementar depois
 * deixaria requisições paralelas passarem juntas. O incremento e a expiração vão na mesma
 * transação, e `EXPIRE ... NX` só define a expiração de uma chave que ainda não tem, então
 * nenhum contador fica sem expiração e a janela é fixa. A cota recusada desfaz o próprio
 * incremento, e um decremento que fica abaixo de zero, porque a janela expirou no meio, é
 * desfeito também.
 */
@Injectable()
export class RegistrationAttemptLimiter {
  constructor(@Inject(LIMITER_REDIS) private readonly redis: Redis) {}

  async countAttempt(ip: string, email: string): Promise<void> {
    const { maxAttempts, attemptWindow } = env.registration();
    const [attempts, ttl] = await this.change(attemptsKey(ip, email), 1, attemptWindow);
    if (attempts > maxAttempts) {
      throw new RegistrationLimited(secondsLeft(ttl));
    }
  }

  async reserveQuota(ip: string): Promise<void> {
    const { maxPerIp, ipWindow } = env.registration();
    const key = quotaKey(ip);
    const [used, ttl] = await this.change(key, 1, ipWindow);
    if (used > maxPerIp) {
      await this.decrement(key, ipWindow);
      throw new RegistrationLimited(secondsLeft(ttl));
    }
  }

  async releaseQuota(ip: string): Promise<void> {
    await this.decrement(quotaKey(ip), env.registration().ipWindow);
  }

  private async decrement(key: string, window: number): Promise<void> {
    const [value] = await this.change(key, -1, window);
    if (value < 0) {
      await this.change(key, 1, window);
    }
  }

  /** Soma `by` à chave e garante a expiração; devolve o valor novo e os segundos restantes. */
  private async change(key: string, by: 1 | -1, window: number): Promise<[number, number]> {
    const transaction = this.redis.multi();
    (by > 0 ? transaction.incr(key) : transaction.decr(key)).expire(key, window, 'NX').ttl(key);
    const results = await transaction.exec();
    if (!results) {
      throw new Error('redis-limiter transaction aborted');
    }
    for (const [error] of results) {
      if (error) throw error;
    }
    return [Number(results[0][1]), Number(results[2][1])];
  }
}

/** No último meio segundo da janela o `TTL` arredonda para 0, e `Retry-After: 0` mandaria tentar antes da hora. */
function secondsLeft(ttl: number): number {
  return Math.max(1, ttl);
}

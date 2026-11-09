import { Inject, Injectable } from '@nestjs/common';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
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

// Os scripts do contrato (docs/api-contract.md › Operação no Redis e Scripts da cota), lidos de
// src, onde o Compose Watch os copia.
const script = (name: string): string =>
  readFileSync(join(process.cwd(), 'src/modules/users/lua', `${name}.lua`), 'utf8');

/**
 * Roda os scripts do contrato no redis-limiter. O contador é comum às três stacks, então a
 * chave e o formato são os do contrato, não os de uma biblioteca de limites.
 */
@Injectable()
export class RegistrationAttemptLimiter {
  private readonly scripts = {
    attempts: script('attempts'),
    reserve: script('reserve'),
    release: script('release'),
  };

  constructor(@Inject(LIMITER_REDIS) private readonly redis: Redis) {}

  async countAttempt(ip: string, email: string): Promise<void> {
    const { maxAttempts, attemptWindow } = env.registration();
    const [attempts, ttl] = (await this.redis.eval(this.scripts.attempts, 1, attemptsKey(ip, email), attemptWindow)) as [
      number,
      number,
    ];
    if (attempts > maxAttempts) {
      throw new RegistrationLimited(Math.max(1, ttl));
    }
  }

  async reserveQuota(ip: string): Promise<void> {
    const { maxPerIp, ipWindow } = env.registration();
    const [reserved, ttl] = (await this.redis.eval(this.scripts.reserve, 1, quotaKey(ip), maxPerIp, ipWindow)) as [
      number,
      number,
    ];
    if (reserved === 0) {
      throw new RegistrationLimited(ttl);
    }
  }

  async releaseQuota(ip: string): Promise<void> {
    await this.redis.eval(this.scripts.release, 1, quotaKey(ip));
  }
}

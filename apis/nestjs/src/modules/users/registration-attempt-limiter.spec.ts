import type Redis from 'ioredis';
import { beforeEach, describe, expect, it } from 'vitest';
import { RegistrationAttemptLimiter, RegistrationLimited } from './registration-attempt-limiter.service';
import { attemptsKey, quotaKey } from './registration-keys';

// O limitador sobre um dublê em memória dos comandos do ioredis que ele usa, com o relógio na
// mão do teste. O comportamento contra o redis-limiter real é provado pelos casos RG de
// tests/infra/registration.sh.

const IP = '203.0.113.10';
const EMAIL = 'ana@example.com';

type Entry = { value: number; expiresAt: number | null };
type Command = () => number;

/** INCR, DECR, EXPIRE ... NX e TTL com a semântica do Redis, em MULTI ... EXEC. */
class FakeRedis {
  now = 1_000_000;
  readonly entries = new Map<string, Entry>();
  /** Chamado depois de cada INCR, com a chave e o valor: um teste pode expirar a chave ali. */
  afterIncr: (key: string, value: number) => void = () => undefined;

  private live(key: string): Entry | undefined {
    const entry = this.entries.get(key);
    if (entry && entry.expiresAt !== null && entry.expiresAt <= this.now) {
      this.entries.delete(key);
      return undefined;
    }
    return entry;
  }

  private add(key: string, by: number): number {
    const entry = this.live(key) ?? { value: 0, expiresAt: null };
    entry.value += by;
    this.entries.set(key, entry);
    return entry.value;
  }

  multi() {
    const commands: Command[] = [];
    const chain = {
      incr: (key: string) => {
        commands.push(() => {
          const value = this.add(key, 1);
          this.afterIncr(key, value);
          return value;
        });
        return chain;
      },
      decr: (key: string) => {
        commands.push(() => this.add(key, -1));
        return chain;
      },
      expire: (key: string, seconds: number, mode: string) => {
        commands.push(() => {
          const entry = this.live(key);
          if (!entry || (mode === 'NX' && entry.expiresAt !== null)) return 0;
          entry.expiresAt = this.now + seconds * 1000;
          return 1;
        });
        return chain;
      },
      ttl: (key: string) => {
        commands.push(() => {
          const entry = this.live(key);
          if (!entry) return -2;
          if (entry.expiresAt === null) return -1;
          return Math.floor((entry.expiresAt - this.now + 500) / 1000);
        });
        return chain;
      },
      exec: async () => commands.map((command) => [null, command()]),
    };
    return chain;
  }

  value(key: string): number | undefined {
    return this.live(key)?.value;
  }

  everyKeyExpires(): boolean {
    return [...this.entries.values()].every((entry) => entry.expiresAt !== null);
  }

  advance(seconds: number): void {
    this.now += seconds * 1000;
  }
}

/** O RegistrationLimited lançado por `call`, ou null quando nada foi lançado. */
async function limitedBy(call: () => Promise<void>): Promise<RegistrationLimited | null> {
  try {
    await call();
  } catch (error) {
    if (error instanceof RegistrationLimited) return error;
    throw error;
  }
  return null;
}

describe('RegistrationAttemptLimiter', () => {
  let redis: FakeRedis;
  let limiter: RegistrationAttemptLimiter;

  const reserveTimes = async (times: number): Promise<void> => {
    for (let i = 0; i < times; i++) await limiter.reserveQuota(IP);
  };

  beforeEach(() => {
    process.env.REGISTRATION_MAX_ATTEMPTS = '5';
    process.env.REGISTRATION_ATTEMPT_WINDOW_SECONDS = '900';
    process.env.REGISTRATION_MAX_PER_IP = '20';
    process.env.REGISTRATION_IP_WINDOW_SECONDS = '3600';
    redis = new FakeRedis();
    limiter = new RegistrationAttemptLimiter(redis as unknown as Redis);
  });

  it('refuses the sixth attempt in the window with the seconds left', async () => {
    for (let i = 1; i <= 5; i++) {
      expect(await limitedBy(() => limiter.countAttempt(IP, EMAIL))).toBeNull();
    }

    const sixth = await limitedBy(() => limiter.countAttempt(IP, EMAIL));
    const seventh = await limitedBy(() => limiter.countAttempt(IP, EMAIL));

    expect(sixth).toBeInstanceOf(RegistrationLimited);
    expect(sixth!.retryAfter).toBe(900);
    expect(seventh).toBeInstanceOf(RegistrationLimited);
  });

  it('keeps the attempt window fixed from the first attempt', async () => {
    await limiter.countAttempt(IP, EMAIL);
    redis.advance(10);
    for (let i = 2; i <= 5; i++) await limiter.countAttempt(IP, EMAIL);

    const sixth = await limitedBy(() => limiter.countAttempt(IP, EMAIL));

    expect(sixth!.retryAfter).toBe(890);
    expect(redis.everyKeyExpires()).toBe(true);
  });

  it('never answers a retry after below one second', async () => {
    redis.entries.set(attemptsKey(IP, EMAIL), { value: 5, expiresAt: redis.now + 400 });

    const limited = await limitedBy(() => limiter.countAttempt(IP, EMAIL));

    expect(limited!.retryAfter).toBe(1);
  });

  it('refuses the twenty-first reservation with the seconds left', async () => {
    for (let i = 1; i <= 20; i++) {
      expect(await limitedBy(() => limiter.reserveQuota(IP))).toBeNull();
    }

    const refused = await limitedBy(() => limiter.reserveQuota(IP));

    expect(refused).toBeInstanceOf(RegistrationLimited);
    expect(refused!.retryAfter).toBe(3600);
  });

  it('leaves the quota at twenty after refused reservations', async () => {
    await reserveTimes(20);

    for (let i = 0; i < 4; i++) {
      expect(await limitedBy(() => limiter.reserveQuota(IP))).toBeInstanceOf(RegistrationLimited);
    }

    expect(redis.value(quotaKey(IP))).toBe(20);
  });

  it('returns a released unit to the quota', async () => {
    await reserveTimes(20);
    await limiter.releaseQuota(IP);

    expect(redis.value(quotaKey(IP))).toBe(19);
    expect(await limitedBy(() => limiter.reserveQuota(IP))).toBeNull();
    expect(await limitedBy(() => limiter.reserveQuota(IP))).toBeInstanceOf(RegistrationLimited);
  });

  it('ignores a release that arrives after the quota window expired', async () => {
    await reserveTimes(1);
    redis.advance(3601);

    await limiter.releaseQuota(IP);

    expect(redis.value(quotaKey(IP)) ?? 0).toBe(0);
    expect(redis.everyKeyExpires()).toBe(true);

    await reserveTimes(20);
    expect(await limitedBy(() => limiter.reserveQuota(IP))).toBeInstanceOf(RegistrationLimited);
  });

  it('undoes an expired refused reservation without going negative', async () => {
    redis.afterIncr = (key, value) => {
      if (key === quotaKey(IP) && value > 20) redis.entries.delete(key);
    };
    await reserveTimes(20);

    expect(await limitedBy(() => limiter.reserveQuota(IP))).toBeInstanceOf(RegistrationLimited);
    expect(redis.value(quotaKey(IP)) ?? 0).toBe(0);
    expect(redis.everyKeyExpires()).toBe(true);
  });

  it('keeps the quota window fixed from the first reservation', async () => {
    await reserveTimes(1);
    await limiter.releaseQuota(IP);
    redis.advance(100);
    await reserveTimes(20);

    const refused = await limitedBy(() => limiter.reserveQuota(IP));

    expect(refused!.retryAfter).toBe(3500);
  });

  it('leaves no counter without an expiry', async () => {
    await reserveTimes(20);
    await limitedBy(() => limiter.reserveQuota(IP));
    await limiter.releaseQuota(IP);
    for (let i = 0; i < 6; i++) await limitedBy(() => limiter.countAttempt(IP, EMAIL));
    redis.advance(3601);
    await limiter.releaseQuota(IP);

    expect(redis.entries.size).toBeGreaterThan(0);
    expect(redis.everyKeyExpires()).toBe(true);
  });
});

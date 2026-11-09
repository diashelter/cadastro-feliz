import { Controller, Get, Inject, Logger, Res } from '@nestjs/common';
import type { Response } from 'express';
import Redis from 'ioredis';
import { Client } from 'pg';
import { env, withTimeout } from '../../config';
import { LIMITER_REDIS } from '../users/registration-attempt-limiter.service';

type CheckResult = 'ok' | 'fail';

/**
 * GET /health, contrato comum às três stacks (docs/api-contract.md › GET /health). Cada check
 * desiste em 1 s e os dois rodam juntos; o motivo de uma falha vai para o log, nunca para o corpo.
 */
@Controller('health')
export class HealthController {
  private readonly logger = new Logger(HealthController.name);

  constructor(@Inject(LIMITER_REDIS) private readonly limiter: Redis) {}

  @Get()
  async health(@Res({ passthrough: true }) res: Response) {
    const [database, limiter] = await Promise.all([
      this.run('database', () => this.database()),
      this.run('limiter', () => this.ping()),
    ]);
    const healthy = database === 'ok' && limiter === 'ok';
    res.status(healthy ? 200 : 503).setHeader('Cache-Control', 'no-store');
    return { status: healthy ? 'ok' : 'fail', checks: { database, limiter } };
  }

  private async run(name: string, check: () => Promise<void>): Promise<CheckResult> {
    try {
      await withTimeout(check(), 1000, `health check ${name}`);
      return 'ok';
    } catch (error) {
      this.logger.error(`health check ${name} failed: ${(error as Error).message}`);
      return 'fail';
    }
  }

  /** Uma conexão própria, e não a do cadastro: um banco travado não prende o pool. */
  private async database(): Promise<void> {
    const client = new Client({ ...env.database(), user: env.database().username, connectionTimeoutMillis: 1000 });
    client.on('error', () => undefined);
    try {
      await client.connect();
      await client.query('select 1');
    } finally {
      void client.end().catch(() => undefined);
    }
  }

  private async ping(): Promise<void> {
    const reply = await this.limiter.ping();
    if (reply !== 'PONG') {
      throw new Error(`unexpected PING reply ${reply}`);
    }
  }
}

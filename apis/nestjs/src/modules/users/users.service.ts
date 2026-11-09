import { Injectable, Logger } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { OutboxRepository } from '../outbox/outbox.repository';
import { RegistrationAttemptLimiter } from './registration-attempt-limiter.service';

export class EmailAlreadyTaken extends Error {}

export interface RegisteredUser {
  id: string;
  name: string;
  email: string;
  created_at: string;
}

/** `2026-11-04T12:00:00Z`: o instante em UTC, sem frações, como nas três stacks. */
const utc = (date: Date): string => `${date.toISOString().slice(0, 19)}Z`;

/**
 * A ordem de processamento do contrato. Este caminho não toca na fila: o relay publica o
 * evento que a transação do cadastro grava.
 */
@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    private readonly limiter: RegistrationAttemptLimiter,
    private readonly outbox: OutboxRepository,
  ) {}

  async register(name: string, email: string, ip: string): Promise<RegisteredUser> {
    const normalizedEmail = email.trim().toLowerCase();

    await this.limiter.countAttempt(ip, normalizedEmail);
    await this.limiter.reserveQuota(ip);

    try {
      return await this.create(name.trim(), normalizedEmail);
    } catch (error) {
      await this.releaseQuota(ip);
      throw error;
    }
  }

  /**
   * Usuário e evento são gravados juntos ou nenhum dos dois (Key decision 1). Sem SELECT
   * prévio: a constraint UNIQUE detecta o e-mail repetido e também resolve duas requisições
   * simultâneas.
   */
  private async create(name: string, email: string): Promise<RegisteredUser> {
    try {
      return await this.dataSource.transaction(async (manager) => {
        const [row]: { id: string; name: string; email: string; created_at: Date }[] = await manager.query(
          'insert into users (name, email) values ($1, $2) returning id, name, email, created_at',
          [name, email],
        );
        const user = { id: row.id, name: row.name, email: row.email, created_at: utc(row.created_at) };
        await this.outbox.recordUserRegistered(manager, {
          user_id: user.id,
          name: user.name,
          email: user.email,
          occurred_at: user.created_at,
        });
        return user;
      });
    } catch (error) {
      const pg = error as { code?: string; constraint?: string; driverError?: { code?: string; constraint?: string } };
      const code = pg.driverError?.code ?? pg.code;
      const constraint = pg.driverError?.constraint ?? pg.constraint;
      if (code === '23505' && constraint === 'users_email_unique') {
        throw new EmailAlreadyTaken();
      }
      throw error;
    }
  }

  private async releaseQuota(ip: string): Promise<void> {
    try {
      await this.limiter.releaseQuota(ip);
    } catch (error) {
      this.logger.error(`registration quota not released: ${(error as Error).message}`);
    }
  }
}

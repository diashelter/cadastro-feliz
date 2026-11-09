import { Injectable } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource, EntityManager } from 'typeorm';
import { env } from '../../config';
import { retryDelaySeconds } from './retry-delay';
import { UserOutboxEvent, UserRegisteredPayload } from './user-outbox-event.entity';

/** As consultas de docs/database.md. Não conhece fila nenhuma: a api também o importa. */
@Injectable()
export class OutboxRepository {
  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  /** Quem chama abre a transação, junto do INSERT em users (Key decision 1). */
  async recordUserRegistered(manager: EntityManager, payload: UserRegisteredPayload): Promise<void> {
    await manager.query(
      "insert into users_outbox (user_id, event_type, payload) values ($1, 'user.registered', $2::jsonb)",
      [payload.user_id, JSON.stringify(payload)],
    );
  }

  /**
   * Publica o lote pronto e só então o marca published, na mesma transação: qualquer falha
   * desfaz o lote, e as mensagens que já saíram viram repetidas, que o consumidor tolera. Duas
   * execuções nunca pegam a mesma linha, de nenhuma stack: quem garante é o SKIP LOCKED.
   */
  async publishReady(publish: (eventId: string) => Promise<void>): Promise<number> {
    const { batchSize, republishAfter } = env.outbox();
    return this.dataSource.transaction(async (manager) => {
      const rows: { id: string }[] = await manager.query(
        `select id from users_outbox
         where (status = 'pending' and available_at <= now())
            or (status = 'published' and published_at <= now() - make_interval(secs => $1))
         order by created_at
         limit $2
         for update skip locked`,
        [republishAfter, batchSize],
      );
      const ids = rows.map((row) => row.id);

      for (const id of ids) {
        await publish(id);
      }

      if (ids.length > 0) {
        await manager.query(
          "update users_outbox set status = 'published', published_at = now() where id = any($1::uuid[])",
          [ids],
        );
      }

      return ids.length;
    });
  }

  find(id: string): Promise<UserOutboxEvent | null> {
    return this.dataSource.getRepository(UserOutboxEvent).findOneBy({ id });
  }

  async markProcessed(id: string): Promise<void> {
    await this.dataSource.query(
      "update users_outbox set status = 'processed', processed_at = now(), last_error = null where id = $1",
      [id],
    );
  }

  async recordFailure(event: UserOutboxEvent, error: string): Promise<void> {
    const { maxAttempts, backoffBase } = env.outbox();
    await this.dataSource.query(
      `update users_outbox
       set attempts = attempts + 1,
           last_error = $1,
           status = case when attempts + 1 >= $2 then 'failed' else 'pending' end,
           available_at = now() + make_interval(secs => $3)
       where id = $4 and status not in ('processed', 'failed')`,
      [error, maxAttempts, retryDelaySeconds(event.attempts, backoffBase), event.id],
    );
  }
}

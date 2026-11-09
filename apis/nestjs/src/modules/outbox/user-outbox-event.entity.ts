import { Column, Entity, PrimaryColumn } from 'typeorm';

export type OutboxStatus = 'pending' | 'published' | 'processed' | 'failed';

/** O `payload` de docs/database.md, o mesmo nas três stacks. */
export interface UserRegisteredPayload {
  user_id: string;
  name: string;
  email: string;
  occurred_at: string;
}

/** A tabela `users_outbox` como database/migrations a cria; o TypeORM só a mapeia. */
@Entity({ name: 'users_outbox' })
export class UserOutboxEvent {
  @PrimaryColumn({ type: 'uuid' })
  id: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId: string;

  @Column({ name: 'event_type', type: 'varchar', length: 100 })
  eventType: string;

  @Column({ type: 'jsonb' })
  payload: UserRegisteredPayload;

  @Column({ type: 'varchar', length: 20 })
  status: OutboxStatus;

  @Column({ type: 'integer' })
  attempts: number;

  @Column({ name: 'last_error', type: 'text', nullable: true })
  lastError: string | null;

  @Column({ name: 'available_at', type: 'timestamptz' })
  availableAt: Date;

  @Column({ name: 'published_at', type: 'timestamptz', nullable: true })
  publishedAt: Date | null;

  @Column({ name: 'processed_at', type: 'timestamptz', nullable: true })
  processedAt: Date | null;

  @Column({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;

  isTerminal(): boolean {
    return this.status === 'processed' || this.status === 'failed';
  }
}

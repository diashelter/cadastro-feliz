import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { typeOrmOptions } from './database';
import { MailModule } from './modules/mail/mail.module';
import { OutboxRelayModule } from './modules/outbox/outbox-relay.module';
import { waitingConnection } from './queues';

/**
 * O módulo raiz do worker (src/worker.ts): o relay e o consumidor de registration-emails. Só
 * ele, e os módulos que só ele importa, registram o BullModule (Key decision 1).
 */
@Module({
  imports: [
    TypeOrmModule.forRoot(typeOrmOptions()),
    BullModule.forRoot({ connection: waitingConnection() }),
    OutboxRelayModule,
    MailModule,
  ],
})
export class WorkerModule {}

import { BullModule } from '@nestjs/bullmq';
import { Inject, Logger, Module, OnApplicationShutdown } from '@nestjs/common';
import { Queue } from 'bullmq';
import { EMAIL_QUEUE, publishingConnection, RELAY_QUEUE } from '../../queues';
import { OutboxModule } from './outbox.module';
import { OutboxRelayProcessor, PUBLISHING_QUEUE } from './outbox-relay.processor';
import { RelayScheduler } from './relay-scheduler.service';

function publishingQueue(): Queue {
  const queue = new Queue(EMAIL_QUEUE, { connection: publishingConnection() });
  const logger = new Logger('PublishingQueue');
  queue.on('error', (error) => logger.warn(`registration-emails publisher: ${error.message}`));
  return queue;
}

/** O relay e o agendador dele. Só do worker. */
@Module({
  imports: [BullModule.registerQueue({ name: RELAY_QUEUE }), OutboxModule],
  providers: [{ provide: PUBLISHING_QUEUE, useFactory: publishingQueue }, OutboxRelayProcessor, RelayScheduler],
})
export class OutboxRelayModule implements OnApplicationShutdown {
  constructor(@Inject(PUBLISHING_QUEUE) private readonly emails: Queue) {}

  async onApplicationShutdown(): Promise<void> {
    await this.emails.close();
  }
}

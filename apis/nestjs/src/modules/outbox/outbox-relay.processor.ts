import { OnWorkerEvent, Processor, WorkerHost } from '@nestjs/bullmq';
import { Inject, Logger } from '@nestjs/common';
import { Queue } from 'bullmq';
import { withTimeout } from '../../config';
import { RELAY_QUEUE } from '../../queues';
import { WELCOME_JOB, welcomeJobData, welcomeJobOptions } from '../mail/welcome-job';
import { OutboxRepository } from './outbox.repository';

export const PUBLISHING_QUEUE = Symbol('PUBLISHING_QUEUE');

/**
 * Uma execução do relay. Só marca published depois de publicar o lote, e qualquer falha desfaz
 * o lote inteiro (Key decision 3). Uma publicação que não termina em 2 s conta como falha, para
 * a fila travada não segurar as travas do lote.
 */
export function relayOnce(events: OutboxRepository, emails: Queue): Promise<number> {
  return events.publishReady(async (eventId) => {
    await withTimeout(
      emails.add(WELCOME_JOB, welcomeJobData(eventId), welcomeJobOptions()),
      2000,
      'publish to registration-emails',
    );
  });
}

/** O relay, disparado a cada segundo pelo agendador da fila outbox-relay. */
@Processor(RELAY_QUEUE)
export class OutboxRelayProcessor extends WorkerHost {
  private readonly logger = new Logger(OutboxRelayProcessor.name);

  constructor(
    private readonly events: OutboxRepository,
    @Inject(PUBLISHING_QUEUE) private readonly emails: Queue,
  ) {
    super();
  }

  async process(): Promise<number> {
    try {
      return await relayOnce(this.events, this.emails);
    } catch (error) {
      this.logger.error(`outbox relay failed: ${(error as Error).message}`);
      throw error;
    }
  }

  @OnWorkerEvent('error')
  onError(error: Error): void {
    this.logger.warn(`outbox-relay worker: ${error.message}`);
  }
}

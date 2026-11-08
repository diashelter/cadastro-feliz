import { OnWorkerEvent, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { EMAIL_QUEUE } from '../../queues';
import { OutboxRepository } from '../outbox/outbox.repository';
import { MailService } from './mail.service';
import { WelcomeJobData } from './welcome-job';

/**
 * Envia o e-mail de boas-vindas a partir do evento. Cada mensagem roda uma vez: sem
 * retentativas do BullMQ, e um job interrompido não volta pela fila (`maxStalledCount` 0),
 * porque as retentativas ficam no banco (Key decision 4). Sem transação aberta durante o
 * envio; só uma falha de envio conta como tentativa.
 */
@Processor(EMAIL_QUEUE, { concurrency: 1, maxStalledCount: 0, lockDuration: 30000 })
export class RegistrationEmailProcessor extends WorkerHost {
  private readonly logger = new Logger(RegistrationEmailProcessor.name);

  constructor(
    private readonly events: OutboxRepository,
    private readonly mail: MailService,
  ) {
    super();
  }

  async process(job: Job<WelcomeJobData>): Promise<void> {
    const eventId = job.data.event_id;
    const event = await this.events.find(eventId);

    if (event === null) {
      this.logger.warn(`outbox event not found: ${eventId}`);
      return;
    }
    if (event.isTerminal()) {
      return;
    }

    try {
      await this.mail.sendWelcome(event.payload.email, event.payload.name, event.id);
    } catch (error) {
      await this.events.recordFailure(event, (error as Error).message);
      return;
    }

    await this.events.markProcessed(event.id);
  }

  @OnWorkerEvent('failed')
  onFailed(job: Job<WelcomeJobData> | undefined, error: Error): void {
    this.logger.error(`welcome email job failed for event ${job?.data.event_id}: ${error.message}`);
  }

  @OnWorkerEvent('error')
  onError(error: Error): void {
    this.logger.warn(`registration-emails worker: ${error.message}`);
  }
}

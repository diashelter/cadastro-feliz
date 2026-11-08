import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { Queue } from 'bullmq';
import { utimesSync, writeFileSync } from 'node:fs';
import { RELAY_EVERY_MS, RELAY_QUEUE, RELAY_SCHEDULER } from '../../queues';

const HEARTBEAT = '/tmp/worker-alive';

/**
 * Mantém o agendador outbox-relay no redis da stack. O redis não tem persistência, então um
 * redis que volta vazio perde o agendador: a cada segundo, com a conexão pronta, ele é
 * registrado de novo se faltar. O mesmo laço renova o arquivo que o healthcheck do worker lê,
 * sem abrir conexão nova com o redis.
 */
@Injectable()
export class RelayScheduler implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger(RelayScheduler.name);
  private timer?: NodeJS.Timeout;
  private busy = false;

  constructor(@InjectQueue(RELAY_QUEUE) private readonly relay: Queue) {}

  onApplicationBootstrap(): void {
    this.relay.on('error', (error) => this.logger.warn(`outbox-relay queue: ${error.message}`));
    void this.tick();
    this.timer = setInterval(() => void this.tick(), 1000);
  }

  onApplicationShutdown(): void {
    clearInterval(this.timer);
  }

  private async tick(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const client = await this.relay.client;
      if (client.status !== 'ready') {
        return;
      }
      if (!(await this.relay.getJobScheduler(RELAY_SCHEDULER))) {
        await this.relay.upsertJobScheduler(RELAY_SCHEDULER, { every: RELAY_EVERY_MS }, {
          name: 'relay',
          opts: { removeOnComplete: true, removeOnFail: true },
        });
        this.logger.log(`job scheduler ${RELAY_SCHEDULER} registered every ${RELAY_EVERY_MS} ms`);
      }
      this.beat();
    } catch (error) {
      this.logger.warn(`job scheduler check failed: ${(error as Error).message}`);
    } finally {
      this.busy = false;
    }
  }

  private beat(): void {
    const now = new Date();
    try {
      utimesSync(HEARTBEAT, now, now);
    } catch {
      writeFileSync(HEARTBEAT, '');
    }
  }
}

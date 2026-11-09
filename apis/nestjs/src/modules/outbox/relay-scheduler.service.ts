import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { Queue } from 'bullmq';
import { utimesSync, writeFileSync } from 'node:fs';
import { RELAY_EVERY_MS, RELAY_QUEUE, RELAY_SCHEDULER } from '../../queues';

const HEARTBEAT = '/tmp/worker-alive';

/**
 * Mantém o agendador outbox-relay no redis da stack. O redis não tem persistência, então um
 * redis que volta vazio perde o agendador: a cada segundo, com a conexão pronta, ele é
 * registrado de novo se faltar. O mesmo vale para um agendador sem próxima execução: o BullMQ só
 * a agenda depois de pegar a atual, numa chamada à parte, e um worker morto entre as duas deixa o
 * agendador sem job nenhum. Como a próxima execução fica pendente desde o instante em que a atual
 * começa, dois laços seguidos sem ela bastam para saber que ela não vem. O mesmo laço renova o
 * arquivo que o healthcheck do worker lê, sem abrir conexão nova com o redis.
 */
@Injectable()
export class RelayScheduler implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger(RelayScheduler.name);
  private timer?: NodeJS.Timeout;
  private busy = false;
  private ticksWithoutNext = 0;

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
        await this.register();
        this.logger.log(`job scheduler ${RELAY_SCHEDULER} registered every ${RELAY_EVERY_MS} ms`);
      } else if (await this.hasNext()) {
        this.ticksWithoutNext = 0;
      } else if (++this.ticksWithoutNext >= 2) {
        await this.register();
        this.logger.warn(`job scheduler ${RELAY_SCHEDULER} had no next run; registered again`);
      }
      this.beat();
    } catch (error) {
      this.logger.warn(`job scheduler check failed: ${(error as Error).message}`);
    } finally {
      this.busy = false;
    }
  }

  private async register(): Promise<void> {
    this.ticksWithoutNext = 0;
    await this.relay.upsertJobScheduler(RELAY_SCHEDULER, { every: RELAY_EVERY_MS }, {
      name: 'relay',
      opts: { removeOnComplete: true, removeOnFail: true },
    });
  }

  /** A próxima execução esperando a vez: agendada, pronta, ou parada com a fila pausada. */
  private async hasNext(): Promise<boolean> {
    const counts = await this.relay.getJobCounts('delayed', 'wait', 'paused', 'prioritized');
    return Object.values(counts).some((count) => count > 0);
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

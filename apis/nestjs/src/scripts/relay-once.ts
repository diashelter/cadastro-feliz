import 'reflect-metadata';
import { Queue } from 'bullmq';
import { DataSource, DataSourceOptions } from 'typeorm';
import { typeOrmOptions } from '../database';
import { OutboxRepository } from '../modules/outbox/outbox.repository';
import { relayOnce } from '../modules/outbox/outbox-relay.processor';
import { EMAIL_QUEUE, publishingConnection } from '../queues';

// Uma execução do relay, fora do agendador, como o `php artisan outbox:relay` da Laravel: o
// mesmo lote, a mesma transação e a mesma conexão de publicação. Imprime `<N> event(s)
// published.` e sai com 0, ou `outbox relay failed` e sai com 1. Roda no container do worker
// com `node dist/scripts/relay-once.js`.

async function main(): Promise<void> {
  const dataSource = new DataSource(typeOrmOptions() as DataSourceOptions);
  const emails = new Queue(EMAIL_QUEUE, { connection: publishingConnection() });
  emails.on('error', () => undefined);
  try {
    await dataSource.initialize();
    const published = await relayOnce(new OutboxRepository(dataSource), emails);
    console.log(`${published} event(s) published.`);
  } finally {
    void emails.close().catch(() => undefined);
    await dataSource.destroy().catch(() => undefined);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(`outbox relay failed: ${error.message}`);
    process.exit(1);
  });

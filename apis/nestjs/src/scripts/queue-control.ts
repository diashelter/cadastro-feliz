import { Queue } from 'bullmq';
import { EMAIL_QUEUE, RELAY_QUEUE, RELAY_SCHEDULER, waitingConnection } from '../queues';
import { WELCOME_JOB, welcomeJobData, welcomeJobOptions } from '../modules/mail/welcome-job';

// As ações nomeadas que tests/infra/adapters/nest.sh pede à stack (decisão 23): pausar e
// retomar um papel do worker, limpar a fila, publicar sem o relay e ler o agendador. Roda no
// container do worker com `node dist/scripts/queue-control.js <ação> [argumento]`.

const QUEUES = new Set([EMAIL_QUEUE, RELAY_QUEUE]);

async function main(action: string, argument?: string): Promise<void> {
  const emails = new Queue(EMAIL_QUEUE, { connection: waitingConnection() });
  const relay = new Queue(RELAY_QUEUE, { connection: waitingConnection() });
  const byName = (name?: string): Queue => {
    if (!name || !QUEUES.has(name)) {
      throw new Error(`unknown queue ${name}`);
    }
    return name === EMAIL_QUEUE ? emails : relay;
  };
  try {
    switch (action) {
      case 'pause':
        await byName(argument).pause();
        break;
      case 'resume':
        await byName(argument).resume();
        break;
      case 'reset':
        await emails.drain(true);
        await emails.clean(0, 0, 'failed');
        await emails.clean(0, 0, 'completed');
        break;
      case 'dispatch':
        if (!argument) {
          throw new Error('dispatch needs an event id');
        }
        await emails.add(WELCOME_JOB, welcomeJobData(argument), welcomeJobOptions());
        break;
      case 'scheduler':
        console.log(JSON.stringify((await relay.getJobScheduler(RELAY_SCHEDULER)) ?? null));
        break;
      default:
        throw new Error(`unknown action ${action}`);
    }
  } finally {
    await Promise.all([emails.close(), relay.close()]);
  }
}

// Com o redis parado, as conexões esperariam para sempre: a ação desiste em 15 s.
setTimeout(() => {
  console.error('queue control timed out');
  process.exit(1);
}, 15000).unref();

main(process.argv[2] ?? '', process.argv[3]).catch((error: Error) => {
  console.error(error.message);
  process.exit(1);
});

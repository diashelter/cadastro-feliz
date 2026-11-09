import type { JobsOptions } from 'bullmq';

// A mensagem de registration-emails, a mesma forma nas três stacks: só o id do evento
// (decisão 10). Nome e e-mail não passam pelo Redis.

export const WELCOME_JOB = 'send-welcome-email';

export interface WelcomeJobData {
  event_id: string;
}

export function welcomeJobData(eventId: string): WelcomeJobData {
  return { event_id: eventId };
}

/**
 * Uma tentativa e sem espera: as retentativas ficam no banco (decisão 9). O id do job é do
 * BullMQ, nunca o do evento, que descartaria a republicação enquanto o job anterior existisse.
 */
export function welcomeJobOptions(): JobsOptions {
  return { attempts: 1, removeOnComplete: true };
}

import { describe, expect, it } from 'vitest';
import { WELCOME_JOB, welcomeJobData, welcomeJobOptions } from './welcome-job';

describe('welcome job', () => {
  it('is added with one attempt and no backoff', () => {
    const options = welcomeJobOptions();
    expect(options.attempts).toBe(1);
    expect(options.backoff).toBeUndefined();
    expect(options.jobId).toBeUndefined();
    expect(WELCOME_JOB).toBe('send-welcome-email');
  });

  it('carries only the event id', () => {
    expect(welcomeJobData('5f0c3d1e-0000-4000-8000-000000000001')).toEqual({
      event_id: '5f0c3d1e-0000-4000-8000-000000000001',
    });
  });
});

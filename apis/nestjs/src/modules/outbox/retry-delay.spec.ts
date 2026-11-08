import { describe, expect, it } from 'vitest';
import { retryDelaySeconds } from './retry-delay';

describe('retry delay', () => {
  it('doubles from the base for attempts 0 to 3', () => {
    expect([0, 1, 2, 3].map((attempts) => retryDelaySeconds(attempts, 30))).toEqual([30, 60, 120, 240]);
    expect(retryDelaySeconds(0, 2)).toBe(2);
    expect(retryDelaySeconds(3, 2)).toBe(16);
  });
});

import { describe, expect, it } from 'vitest';
import { attemptsKey, canonicalIp } from './registration-keys';

describe('registration keys', () => {
  it('matches the contract example', () => {
    expect(attemptsKey('203.0.113.10', 'ana@example.com')).toBe(
      'registration:attempts:da657b591c8d33639918ea46be3b50e2bb1173313d08cf019556c130426a63a8',
    );
  });

  it('canonicalizes the client ip', () => {
    expect(canonicalIp('::ffff:203.0.113.10')).toBe('203.0.113.10');
    expect(canonicalIp('::FFFF:CB00:710A')).toBe('203.0.113.10');
    expect(canonicalIp('2001:DB8:0:0:0:0:0:1')).toBe('2001:db8::1');
    expect(canonicalIp('fe80::1%eth0')).toBe('fe80::1');
    expect(canonicalIp('2001:db8:0:1:0:0:1:1')).toBe('2001:db8:0:1::1:1');
    expect(canonicalIp('2001:db8:0:1:1:1:1:1')).toBe('2001:db8:0:1:1:1:1:1');
  });
});

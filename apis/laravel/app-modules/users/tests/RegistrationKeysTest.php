<?php

use Modules\Users\Services\RegistrationKeys;

const ATTEMPT_KEY = 'registration:attempts:da657b591c8d33639918ea46be3b50e2bb1173313d08cf019556c130426a63a8';
const QUOTA_KEY = 'registration:ip:631f08140b24b7274d12df3c37a1a80ce5876dafd7007d772e0114fddf88b682';

it('builds the attempt key from the contract example', function () {
    expect(RegistrationKeys::attempts('203.0.113.10', 'ana@example.com'))->toBe(ATTEMPT_KEY);
});

it('builds the quota key from the contract example', function () {
    expect(RegistrationKeys::quota('203.0.113.10'))->toBe(QUOTA_KEY);
});

it('maps an ipv4 mapped address to the same keys', function () {
    expect(RegistrationKeys::attempts('::ffff:203.0.113.10', 'ana@example.com'))->toBe(ATTEMPT_KEY)
        ->and(RegistrationKeys::quota('::ffff:203.0.113.10'))->toBe(QUOTA_KEY);
});

it('compresses and lowers an ipv6 address', function () {
    expect(RegistrationKeys::canonicalIp('2001:DB8:0:0::1'))->toBe('2001:db8::1')
        ->and(RegistrationKeys::canonicalIp('2001:DB8:0:0::1%eth0'))->toBe('2001:db8::1')
        ->and(RegistrationKeys::quota('2001:DB8:0:0::1'))->toBe('registration:ip:'.hash('sha256', '2001:db8::1'));
});

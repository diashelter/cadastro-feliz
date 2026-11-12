<?php

use Illuminate\Cache\ArrayStore;
use Illuminate\Support\Facades\Cache;
use Modules\Users\Exceptions\RegistrationLimited;
use Modules\Users\Services\RegistrationKeys;
use Modules\Users\Services\RegistrationLimiter;

// O limitador sobre o cache store `limiter`, aqui em memória. O comportamento contra o
// redis-limiter real é provado pelos casos RG de tests/infra/registration.sh.

const LIMITER_IP = '203.0.113.10';
const LIMITER_EMAIL = 'ana@example.com';

/** Um ArrayStore que apaga a chave da cota quando ela passa do limite, como uma janela expirando entre dois comandos. */
class ExpiringQuotaStore extends ArrayStore
{
    public function increment($key, $value = 1)
    {
        $result = parent::increment($key, $value);

        if ($key === RegistrationKeys::quota(LIMITER_IP) && $result > 20) {
            $this->forget($key);
            $this->forget($key.':timer');
        }

        return $result;
    }
}

beforeEach(function () {
    config([
        'cache.stores.limiter' => ['driver' => 'array', 'serialize' => false],
        'registration.max_attempts' => 5,
        'registration.attempt_window' => 900,
        'registration.max_per_ip' => 20,
        'registration.ip_window' => 3600,
    ]);
});

function limiter(): RegistrationLimiter
{
    return app(RegistrationLimiter::class);
}

/** O RegistrationLimited lançado por $call, ou null quando nada foi lançado. */
function limitedBy(Closure $call): ?RegistrationLimited
{
    try {
        $call();
    } catch (RegistrationLimited $e) {
        return $e;
    }

    return null;
}

function quotaCount(): int
{
    return (int) Cache::store('limiter')->get(RegistrationKeys::quota(LIMITER_IP), 0);
}

/** Toda chave do store em memória tem expiração. */
function everyKeyExpires(): bool
{
    $store = Cache::store('limiter')->getStore();
    $storage = (fn () => $this->storage)->call($store);

    foreach ($storage as $item) {
        if ($item['expiresAt'] === 0 || $item['expiresAt'] === 0.0) {
            return false;
        }
    }

    return true;
}

function reserveTimes(int $times): void
{
    for ($i = 0; $i < $times; $i++) {
        limiter()->reserveQuota(LIMITER_IP);
    }
}

it('refuses the sixth attempt in the window with the seconds left', function () {
    for ($i = 1; $i <= 5; $i++) {
        expect(limitedBy(fn () => limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL)))->toBeNull();
    }

    $sixth = limitedBy(fn () => limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL));
    $seventh = limitedBy(fn () => limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL));

    expect($sixth)->toBeInstanceOf(RegistrationLimited::class)
        ->and($sixth->retryAfter)->toBeGreaterThanOrEqual(1)->toBeLessThanOrEqual(900)
        ->and($seventh)->toBeInstanceOf(RegistrationLimited::class);
});

it('keeps the attempt window fixed from the first attempt', function () {
    limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL);
    $this->travel(10)->seconds();

    for ($i = 2; $i <= 5; $i++) {
        limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL);
    }

    $sixth = limitedBy(fn () => limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL));

    expect($sixth->retryAfter)->toBeGreaterThanOrEqual(1)->toBeLessThanOrEqual(890)
        ->and(everyKeyExpires())->toBeTrue();
});

it('never answers a retry after below one second', function () {
    $key = RegistrationKeys::attempts(LIMITER_IP, LIMITER_EMAIL);
    Cache::store('limiter')->put($key, 5, 1000);
    Cache::store('limiter')->put($key.':timer', now()->getTimestamp(), 1000);

    $limited = limitedBy(fn () => limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL));

    expect($limited->retryAfter)->toBe(1);
});

it('refuses the twenty-first reservation with the seconds left', function () {
    for ($i = 1; $i <= 20; $i++) {
        expect(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeNull();
    }

    $refused = limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP));

    expect($refused)->toBeInstanceOf(RegistrationLimited::class)
        ->and($refused->retryAfter)->toBeGreaterThanOrEqual(1)->toBeLessThanOrEqual(3600);
});

it('leaves the quota at twenty after refused reservations', function () {
    reserveTimes(19);
    reserveTimes(1);

    for ($i = 0; $i < 4; $i++) {
        expect(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeInstanceOf(RegistrationLimited::class);
    }

    expect(quotaCount())->toBe(20);
});

it('returns a released unit to the quota', function () {
    reserveTimes(20);
    limiter()->releaseQuota(LIMITER_IP);

    expect(quotaCount())->toBe(19)
        ->and(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeNull()
        ->and(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeInstanceOf(RegistrationLimited::class);
});

it('ignores a release that arrives after the quota window expired', function () {
    reserveTimes(1);
    $this->travel(3601)->seconds();

    limiter()->releaseQuota(LIMITER_IP);

    expect(quotaCount())->toBe(0)
        ->and(everyKeyExpires())->toBeTrue();

    reserveTimes(20);

    expect(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeInstanceOf(RegistrationLimited::class);
});

it('undoes an expired refused reservation without going negative', function () {
    Cache::extend('expiring-quota', fn () => Cache::repository(new ExpiringQuotaStore));
    config(['cache.stores.limiter' => ['driver' => 'expiring-quota']]);

    reserveTimes(20);

    expect(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeInstanceOf(RegistrationLimited::class)
        ->and(quotaCount())->toBe(0)
        ->and(everyKeyExpires())->toBeTrue();
});

it('keeps the quota window fixed from the first reservation', function () {
    reserveTimes(1);
    $this->travel(100)->seconds();
    reserveTimes(19);

    $refused = limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP));

    expect($refused->retryAfter)->toBeGreaterThanOrEqual(1)->toBeLessThanOrEqual(3500)
        ->and(everyKeyExpires())->toBeTrue();
});

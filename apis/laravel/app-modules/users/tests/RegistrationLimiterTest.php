<?php

use Illuminate\Contracts\Redis\Factory as RedisFactory;
use Modules\Users\Exceptions\RegistrationLimited;
use Modules\Users\Services\RegistrationKeys;
use Modules\Users\Services\RegistrationLimiter;

// O limitador sobre um dublê em memória do cliente da conexão `limiter`, com INCRBY, EXPIRE ... NX
// e TTL em MULTI ... EXEC e o relógio do teste. O comportamento contra o redis-limiter real é provado
// pelos casos RG de tests/infra/registration.sh.

const LIMITER_IP = '203.0.113.10';
const LIMITER_EMAIL = 'ana@example.com';

/** INCRBY, EXPIRE ... NX e TTL com a semântica do Redis, executados juntos no EXEC. */
class FakeLimiterRedis implements RedisFactory
{
    /** @var array<string, array{value: int, expiresAt: ?int}> */
    public array $entries = [];

    /** Chamado depois de cada INCRBY, com a chave e o valor: um teste pode expirar a chave ali. */
    public ?Closure $afterIncr = null;

    public function connection($name = null)
    {
        return $this;
    }

    private function now(): int
    {
        return (int) now()->getPreciseTimestamp(3);
    }

    /** @return array{value: int, expiresAt: ?int}|null */
    private function live(string $key): ?array
    {
        $entry = $this->entries[$key] ?? null;

        if ($entry !== null && $entry['expiresAt'] !== null && $entry['expiresAt'] <= $this->now()) {
            unset($this->entries[$key]);

            return null;
        }

        return $entry;
    }

    public function client(): static
    {
        return $this;
    }

    /** MULTI: guarda os comandos encadeados e executa todos juntos no exec(). */
    public function multi(): object
    {
        $redis = $this;

        return new class($redis)
        {
            private array $commands = [];

            public function __construct(private FakeLimiterRedis $redis) {}

            public function __call($method, $arguments)
            {
                $this->commands[] = [$method, $arguments];

                return $this;
            }

            public function exec(): array
            {
                return array_map(fn ($command) => $this->redis->run($command[0], $command[1]), $this->commands);
            }
        };
    }

    public function run(string $command, array $arguments): mixed
    {
        return $this->{'run'.ucfirst(strtolower($command))}(...$arguments);
    }

    private function runIncrby(string $key, int $by): int
    {
        $entry = $this->live($key) ?? ['value' => 0, 'expiresAt' => null];
        $entry['value'] += $by;
        $this->entries[$key] = $entry;

        if ($this->afterIncr !== null) {
            ($this->afterIncr)($key, $entry['value']);
        }

        return $entry['value'];
    }

    private function runExpire(string $key, int $seconds, string $mode): bool
    {
        $entry = $this->live($key);

        if ($entry === null || ($mode === 'NX' && $entry['expiresAt'] !== null)) {
            return false;
        }

        $this->entries[$key]['expiresAt'] = $this->now() + $seconds * 1000;

        return true;
    }

    private function runTtl(string $key): int
    {
        $entry = $this->live($key);

        if ($entry === null) {
            return -2;
        }

        if ($entry['expiresAt'] === null) {
            return -1;
        }

        return intdiv($entry['expiresAt'] - $this->now() + 500, 1000);
    }

    public function value(string $key): ?int
    {
        return $this->live($key)['value'] ?? null;
    }

    public function everyKeyExpires(): bool
    {
        foreach ($this->entries as $entry) {
            if ($entry['expiresAt'] === null) {
                return false;
            }
        }

        return true;
    }
}

beforeEach(function () {
    config([
        'registration.max_attempts' => 5,
        'registration.attempt_window' => 900,
        'registration.max_per_ip' => 20,
        'registration.ip_window' => 3600,
    ]);
    $this->freezeTime();
    $this->redis = new FakeLimiterRedis;
    $this->app->instance(RedisFactory::class, $this->redis);
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
        ->and($sixth->retryAfter)->toBe(900)
        ->and($seventh)->toBeInstanceOf(RegistrationLimited::class);
});

it('keeps the attempt window fixed from the first attempt', function () {
    limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL);
    $this->travel(10)->seconds();

    for ($i = 2; $i <= 5; $i++) {
        limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL);
    }

    $sixth = limitedBy(fn () => limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL));

    expect($sixth->retryAfter)->toBe(890)
        ->and($this->redis->everyKeyExpires())->toBeTrue();
});

it('never answers a retry after below one second', function () {
    $this->redis->entries[RegistrationKeys::attempts(LIMITER_IP, LIMITER_EMAIL)] = [
        'value' => 5,
        'expiresAt' => (int) now()->getPreciseTimestamp(3) + 400,
    ];

    $limited = limitedBy(fn () => limiter()->countAttempt(LIMITER_IP, LIMITER_EMAIL));

    expect($limited->retryAfter)->toBe(1);
});

it('refuses the twenty-first reservation with the seconds left', function () {
    for ($i = 1; $i <= 20; $i++) {
        expect(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeNull();
    }

    $refused = limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP));

    expect($refused)->toBeInstanceOf(RegistrationLimited::class)
        ->and($refused->retryAfter)->toBe(3600);
});

it('leaves the quota at twenty after refused reservations', function () {
    reserveTimes(20);

    for ($i = 0; $i < 4; $i++) {
        expect(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeInstanceOf(RegistrationLimited::class);
    }

    expect($this->redis->value(RegistrationKeys::quota(LIMITER_IP)))->toBe(20);
});

it('returns a released unit to the quota', function () {
    reserveTimes(20);
    limiter()->releaseQuota(LIMITER_IP);

    expect($this->redis->value(RegistrationKeys::quota(LIMITER_IP)))->toBe(19)
        ->and(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeNull()
        ->and(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeInstanceOf(RegistrationLimited::class);
});

it('ignores a release that arrives after the quota window expired', function () {
    reserveTimes(1);
    $this->travel(3601)->seconds();

    limiter()->releaseQuota(LIMITER_IP);

    expect($this->redis->value(RegistrationKeys::quota(LIMITER_IP)) ?? 0)->toBe(0)
        ->and($this->redis->everyKeyExpires())->toBeTrue();

    reserveTimes(20);

    expect(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeInstanceOf(RegistrationLimited::class);
});

it('undoes an expired refused reservation without going negative', function () {
    $this->redis->afterIncr = function (string $key, int $value) {
        if ($key === RegistrationKeys::quota(LIMITER_IP) && $value > 20) {
            unset($this->redis->entries[$key]);
        }
    };
    reserveTimes(20);

    expect(limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP)))->toBeInstanceOf(RegistrationLimited::class)
        ->and($this->redis->value(RegistrationKeys::quota(LIMITER_IP)) ?? 0)->toBe(0)
        ->and($this->redis->everyKeyExpires())->toBeTrue();
});

it('keeps the quota window fixed from the first reservation', function () {
    reserveTimes(1);
    limiter()->releaseQuota(LIMITER_IP);
    $this->travel(100)->seconds();
    reserveTimes(20);

    $refused = limitedBy(fn () => limiter()->reserveQuota(LIMITER_IP));

    expect($refused->retryAfter)->toBe(3500)
        ->and($this->redis->everyKeyExpires())->toBeTrue();
});

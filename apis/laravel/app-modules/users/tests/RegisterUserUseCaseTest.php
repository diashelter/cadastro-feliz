<?php

use Illuminate\Support\Facades\DB;
use Modules\Users\Models\User;
use Modules\Users\Repositories\OutboxRepository;
use Modules\Users\Repositories\UserRepository;
use Modules\Users\Services\RegistrationLimiter;
use Modules\Users\UseCases\RegisterUser;

function registeredUser(): User
{
    return (new User)->newFromBuilder((object) [
        'id' => '0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e',
        'name' => 'Ana Souza',
        'email' => 'ana@example.com',
        'created_at' => '2026-11-04 09:00:00-03',
        'updated_at' => '2026-11-04 09:00:00-03',
    ]);
}

/** DB::transaction registra o início e o fim em $log; runs = false não executa o callback. */
function recordTransaction(array &$log, bool $runs = true): void
{
    DB::shouldReceive('transaction')->once()->andReturnUsing(function (Closure $callback) use (&$log, $runs) {
        $log[] = 'begin';
        $result = $runs ? $callback() : registeredUser();
        $log[] = 'commit';

        return $result;
    });
}

function quietLimiter(): RegistrationLimiter
{
    $limiter = Mockery::mock(RegistrationLimiter::class);
    $limiter->shouldReceive('countAttempt', 'reserveQuota')->byDefault();

    return $limiter;
}

it('writes the user and the event inside one transaction', function () {
    $log = [];
    $users = Mockery::mock(UserRepository::class);
    $users->shouldReceive('create')->once()->with('Ana Souza', 'ana@example.com')
        ->andReturnUsing(function () use (&$log) {
            $log[] = 'users';

            return registeredUser();
        });
    $outbox = Mockery::mock(OutboxRepository::class);
    $outbox->shouldReceive('recordUserRegistered')->once()
        ->with('0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e', 'Ana Souza', 'ana@example.com', '2026-11-04T12:00:00Z')
        ->andReturnUsing(function () use (&$log) {
            $log[] = 'users_outbox';
        });

    recordTransaction($log);
    $user = (new RegisterUser(quietLimiter(), $users, $outbox))
        ->execute('  Ana Souza ', ' ANA@Example.com ', '10.0.0.1');

    expect($log)->toBe(['begin', 'users', 'users_outbox', 'commit'])
        ->and($user->id)->toBe('0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e');
});

it('writes nothing when the transaction does not run', function () {
    $log = [];
    $users = Mockery::mock(UserRepository::class);
    $users->shouldNotReceive('create');
    $outbox = Mockery::mock(OutboxRepository::class);
    $outbox->shouldNotReceive('recordUserRegistered');

    recordTransaction($log, runs: false);
    (new RegisterUser(quietLimiter(), $users, $outbox))
        ->execute('Ana Souza', 'ana@example.com', '10.0.0.1');

    expect($log)->toBe(['begin', 'commit']);
});

it('rethrows an event failure and releases the quota once', function () {
    $failure = new RuntimeException('outbox insert failed');
    $escaped = null;
    DB::shouldReceive('transaction')->once()->andReturnUsing(function (Closure $callback) use (&$escaped) {
        try {
            return $callback();
        } catch (Throwable $e) {
            $escaped = $e;

            throw $e;
        }
    });
    $limiter = quietLimiter();
    $limiter->shouldReceive('releaseQuota')->once()->with('10.0.0.1');
    $users = Mockery::mock(UserRepository::class);
    $users->shouldReceive('create')->once()->andReturn(registeredUser());
    $outbox = Mockery::mock(OutboxRepository::class);
    $outbox->shouldReceive('recordUserRegistered')->once()->andThrow($failure);

    expect(fn () => (new RegisterUser($limiter, $users, $outbox))->execute('Ana Souza', 'ana@example.com', '10.0.0.1'))
        ->toThrow(RuntimeException::class, 'outbox insert failed');
    expect($escaped)->toBe($failure);
});

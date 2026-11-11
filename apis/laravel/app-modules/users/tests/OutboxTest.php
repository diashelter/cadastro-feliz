<?php

use Modules\Users\Enums\OutboxEventType;
use Modules\Users\Enums\OutboxStatus;
use Modules\Users\Models\UserOutboxEvent;
use Modules\Users\Services\RetryPolicy;

it('lists the statuses and which are terminal', function () {
    expect(array_map(fn (OutboxStatus $s) => [$s->value, $s->isTerminal()], OutboxStatus::cases()))->toBe([
        ['pending', false],
        ['published', false],
        ['processed', true],
        ['failed', true],
    ]);
});

it('has only the user registered event type', function () {
    expect(OutboxEventType::cases())->toBe([OutboxEventType::UserRegistered])
        ->and(OutboxEventType::UserRegistered->value)->toBe('user.registered');
});

it('casts the outbox row to the enums', function () {
    $event = (new UserOutboxEvent)->newFromBuilder((object) [
        'id' => '0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e',
        'event_type' => 'user.registered',
        'status' => 'failed',
        'attempts' => 5,
    ]);

    expect($event->status)->toBe(OutboxStatus::Failed)
        ->and($event->event_type)->toBe(OutboxEventType::UserRegistered)
        ->and($event->isTerminal())->toBeTrue()
        ->and(defined(UserOutboxEvent::class.'::TERMINAL_STATUSES'))->toBeFalse();

    $code = [];
    foreach (['app', 'app-modules', 'bootstrap', 'config', 'routes'] as $dir) {
        foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator(base_path($dir), FilesystemIterator::SKIP_DOTS)) as $file) {
            if ($file->getExtension() === 'php' && ! str_contains($file->getPathname(), '/tests/')) {
                $code[$file->getPathname()] = file_get_contents($file->getPathname());
            }
        }
    }
    expect($code)->toHaveKey(base_path('app-modules/users/src/Models/UserOutboxEvent.php'))
        ->and(array_keys(array_filter($code, fn (string $c) => str_contains($c, 'TERMINAL_STATUSES'))))->toBe([]);
});

it('waits base times two to the previous attempts', function () {
    expect(array_map(fn (int $previous) => RetryPolicy::delaySeconds($previous, 30), [0, 1, 2, 3]))
        ->toBe([30, 60, 120, 240])
        ->and(RetryPolicy::delaySeconds(0, 2))->toBe(2);
});

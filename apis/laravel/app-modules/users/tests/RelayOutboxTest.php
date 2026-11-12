<?php

use Illuminate\Contracts\Bus\Dispatcher;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Modules\Users\Jobs\SendWelcomeEmailJob;
use Modules\Users\Repositories\OutboxRepository;
use Modules\Users\UseCases\RelayOutboxEvents;

/** DB::transaction registra o início e o fim em $log e executa o callback. */
function relayTransaction(array &$log): void
{
    DB::shouldReceive('transaction')->once()->andReturnUsing(function (Closure $callback) use (&$log) {
        $log[] = 'begin';
        $result = $callback();
        $log[] = 'commit';

        return $result;
    });
}

/** @param  list<array{0: string, 1: string}>  $rows  [id, event_type] */
function relayOutbox(array &$log, array $rows): OutboxRepository
{
    $outbox = Mockery::mock(OutboxRepository::class);
    $outbox->shouldReceive('lockReadyBatch')->once()->andReturnUsing(function () use (&$log, $rows) {
        $log[] = 'lock';

        return array_map(fn (array $r) => (object) ['id' => $r[0], 'event_type' => $r[1]], $rows);
    });
    $outbox->shouldReceive('markPublished')->andReturnUsing(function (array $ids) use (&$log) {
        $log[] = 'mark '.implode(',', $ids);
    });

    return $outbox;
}

/** Um barramento que registra cada job publicado em $log e o guarda em $jobs. */
function relayBus(array &$log, array &$jobs = []): Dispatcher
{
    $bus = Mockery::mock(Dispatcher::class);
    $bus->shouldReceive('dispatch')->andReturnUsing(function (object $job) use (&$log, &$jobs) {
        $log[] = 'publish '.$job->eventId;
        $jobs[] = $job;
    });

    return $bus;
}

it('locks, publishes and marks the batch inside one transaction', function () {
    $log = [];
    relayTransaction($log);
    $outbox = relayOutbox($log, [['e1', 'user.registered'], ['e2', 'user.registered']]);

    $published = (new RelayOutboxEvents($outbox, relayBus($log)))->execute();

    expect($published)->toBe(2)
        ->and($log)->toBe(['begin', 'lock', 'publish e1', 'publish e2', 'mark e1,e2', 'commit']);
});

it('publishes and marks nothing for an empty batch', function () {
    $log = [];
    relayTransaction($log);
    $outbox = relayOutbox($log, []);
    $outbox->shouldNotReceive('markPublished');

    $published = (new RelayOutboxEvents($outbox, relayBus($log)))->execute();

    expect($published)->toBe(0)
        ->and($log)->toBe(['begin', 'lock', 'commit']);
});

it('publishes the welcome email job for user registered', function () {
    $log = [];
    $jobs = [];
    relayTransaction($log);

    (new RelayOutboxEvents(relayOutbox($log, [['e1', 'user.registered']]), relayBus($log, $jobs)))->execute();

    expect($jobs)->toHaveCount(1)
        ->and($jobs[0])->toBeInstanceOf(SendWelcomeEmailJob::class)
        ->and($jobs[0]->eventId)->toBe('e1');
});

it('publishes nothing when an event type is unknown', function () {
    $cases = [
        'só o tipo desconhecido' => [[['e1', 'user.deleted']], 'user.deleted'],
        '3º de 3 desconhecido' => [[['e1', 'user.registered'], ['e2', 'user.registered'], ['e3', 'user.deleted']], 'user.deleted'],
    ];

    DB::shouldReceive('transaction')->times(count($cases))->andReturnUsing(fn (Closure $callback) => $callback());

    foreach ($cases as $name => [$rows, $type]) {
        $log = [];
        $outbox = relayOutbox($log, $rows);
        $outbox->shouldNotReceive('markPublished');

        try {
            (new RelayOutboxEvents($outbox, relayBus($log)))->execute();
            $thrown = null;
        } catch (Throwable $e) {
            $thrown = $e;
        }

        expect($thrown)->not->toBeNull("{$name}: sem exceção")
            ->and($thrown->getMessage())->toContain($type)
            ->and($log)->toBe(['lock']);
    }
});

it('exits 1 and logs when the relay fails', function () {
    $this->mock(RelayOutboxEvents::class)->shouldReceive('execute')->once()
        ->andThrow(new RuntimeException('relay boom'));
    Log::shouldReceive('error')->once()
        ->with('outbox relay failed', Mockery::on(fn (array $context) => str_contains($context['error'], 'relay boom')));

    $this->artisan('outbox:relay')->assertExitCode(1);
});

it('prints the published count', function () {
    $this->mock(RelayOutboxEvents::class)->shouldReceive('execute')->once()->andReturn(3);

    $this->artisan('outbox:relay')->expectsOutput('3 event(s) published.')->assertExitCode(0);
});

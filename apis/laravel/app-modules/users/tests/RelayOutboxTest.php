<?php

use Illuminate\Contracts\Bus\Dispatcher;
use Illuminate\Database\ConnectionInterface;
use Illuminate\Support\Facades\Log;
use Modules\Users\Enums\OutboxEventType;
use Modules\Users\Exceptions\UnknownOutboxConsumer;
use Modules\Users\Repositories\OutboxRepository;
use Modules\Users\Services\OutboxConsumers;
use Modules\Users\UseCases\RelayOutboxEvents;

/** Um job qualquer: este módulo não conhece os consumidores de verdade. */
final class RelayProbeJob
{
    public function __construct(public string $eventId) {}
}

function relayConnection(array &$log): ConnectionInterface
{
    $db = Mockery::mock(ConnectionInterface::class);
    $db->shouldReceive('transaction')->once()->andReturnUsing(function (Closure $callback) use (&$log) {
        $log[] = 'begin';
        $result = $callback();
        $log[] = 'commit';

        return $result;
    });

    return $db;
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

function relayBus(array &$log): Dispatcher
{
    $bus = Mockery::mock(Dispatcher::class);
    $bus->shouldReceive('dispatch')->andReturnUsing(function (RelayProbeJob $job) use (&$log) {
        $log[] = 'publish '.$job->eventId;
    });

    return $bus;
}

function probeConsumers(): OutboxConsumers
{
    $consumers = new OutboxConsumers;
    $consumers->register(OutboxEventType::UserRegistered, fn (string $id) => new RelayProbeJob($id));

    return $consumers;
}

it('locks, publishes and marks the batch inside one transaction', function () {
    $log = [];
    $outbox = relayOutbox($log, [['e1', 'user.registered'], ['e2', 'user.registered']]);

    $published = (new RelayOutboxEvents(relayConnection($log), $outbox, probeConsumers(), relayBus($log)))->execute();

    expect($published)->toBe(2)
        ->and($log)->toBe(['begin', 'lock', 'publish e1', 'publish e2', 'mark e1,e2', 'commit']);
});

it('publishes and marks nothing for an empty batch', function () {
    $log = [];
    $outbox = relayOutbox($log, []);
    $outbox->shouldNotReceive('markPublished');

    $published = (new RelayOutboxEvents(relayConnection($log), $outbox, probeConsumers(), relayBus($log)))->execute();

    expect($published)->toBe(0)
        ->and($log)->toBe(['begin', 'lock', 'commit']);
});

it('publishes nothing when an event type has no consumer', function () {
    $cases = [
        'registro vazio' => [new OutboxConsumers, [['e1', 'user.registered']], 'user.registered'],
        '3º de 3 sem consumidor' => [probeConsumers(), [['e1', 'user.registered'], ['e2', 'user.registered'], ['e3', 'user.deleted']], 'user.deleted'],
    ];

    foreach ($cases as $name => [$consumers, $rows, $type]) {
        $log = [];
        $outbox = relayOutbox($log, $rows);
        $outbox->shouldNotReceive('markPublished');
        $db = Mockery::mock(ConnectionInterface::class);
        $db->shouldReceive('transaction')->once()->andReturnUsing(fn (Closure $callback) => $callback());

        try {
            (new RelayOutboxEvents($db, $outbox, $consumers, relayBus($log)))->execute();
            $thrown = null;
        } catch (UnknownOutboxConsumer $e) {
            $thrown = $e;
        }

        expect($thrown)->not->toBeNull("{$name}: sem exceção")
            ->and($thrown->getMessage())->toContain($type)
            ->and($log)->toBe(['lock']);
    }
});

it('exits 1 and logs when the relay fails', function () {
    $this->mock(RelayOutboxEvents::class)->shouldReceive('execute')->once()
        ->andThrow(new UnknownOutboxConsumer('user.registered'));
    Log::shouldReceive('error')->once()
        ->with('outbox relay failed', Mockery::on(fn (array $context) => str_contains($context['error'], 'user.registered')));

    $this->artisan('outbox:relay')->assertExitCode(1);
});

it('prints the published count', function () {
    $this->mock(RelayOutboxEvents::class)->shouldReceive('execute')->once()->andReturn(3);

    $this->artisan('outbox:relay')->expectsOutput('3 event(s) published.')->assertExitCode(0);
});

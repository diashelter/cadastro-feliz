<?php

namespace Modules\Users\Services;

use Closure;
use Illuminate\Container\Attributes\Singleton;
use Modules\Users\Enums\OutboxEventType;
use Modules\Users\Exceptions\UnknownOutboxConsumer;

/**
 * Quem consome cada tipo de evento do outbox. Os módulos consumidores se registram aqui, e
 * assim users publica sem depender deles. Um tipo sem consumidor é erro, nunca um evento
 * marcado published sem ninguém para processá-lo.
 */
#[Singleton]
class OutboxConsumers
{
    /** @var array<string, Closure(string): object> */
    private array $jobs = [];

    /** @param  Closure(string $eventId): object  $job  o job a publicar na fila para o evento */
    public function register(OutboxEventType $type, Closure $job): void
    {
        $this->jobs[$type->value] = $job;
    }

    /** @throws UnknownOutboxConsumer */
    public function jobFor(string $eventType, string $eventId): object
    {
        $job = $this->jobs[$eventType] ?? throw new UnknownOutboxConsumer($eventType);

        return $job($eventId);
    }
}

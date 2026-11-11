<?php

namespace Modules\Users\Exceptions;

use RuntimeException;

/** Um evento cujo tipo nenhum módulo registrou em OutboxConsumers. */
class UnknownOutboxConsumer extends RuntimeException
{
    public function __construct(public readonly string $eventType)
    {
        parent::__construct("no outbox consumer for event type {$eventType}");
    }
}

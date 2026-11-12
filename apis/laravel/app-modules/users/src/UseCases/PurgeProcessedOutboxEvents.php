<?php

namespace Modules\Users\UseCases;

use InvalidArgumentException;
use Modules\Users\Repositories\OutboxRepository;

/**
 * Apaga os eventos processed concluídos há mais de OUTBOX_RETENTION_DAYS dias. Nenhum outro
 * status sai do banco: failed fica até o reprocessamento manual de docs/database.md.
 */
class PurgeProcessedOutboxEvents
{
    public function __construct(private OutboxRepository $events) {}

    public function execute(): int
    {
        $days = (int) config('outbox.retention_days');

        // Um prazo zerado por um .env vazio apagaria todo evento processed de uma vez.
        if ($days < 1) {
            throw new InvalidArgumentException("OUTBOX_RETENTION_DAYS must be at least 1, got {$days}");
        }

        return $this->events->purgeProcessedOlderThan($days);
    }
}

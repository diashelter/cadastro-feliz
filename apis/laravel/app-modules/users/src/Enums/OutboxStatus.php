<?php

namespace Modules\Users\Enums;

/**
 * O status de uma linha de users_outbox. Os valores são os do CHECK users_outbox_status_valid,
 * lidos também pelas outras stacks; o ciclo está em docs/database.md.
 */
enum OutboxStatus: string
{
    case Pending = 'pending';
    case Published = 'published';
    case Processed = 'processed';
    case Failed = 'failed';

    public function isTerminal(): bool
    {
        return $this === self::Processed || $this === self::Failed;
    }
}

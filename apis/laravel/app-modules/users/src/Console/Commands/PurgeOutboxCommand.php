<?php

namespace Modules\Users\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;
use Modules\Users\UseCases\PurgeProcessedOutboxEvents;
use Throwable;

/** Agendado uma vez por dia; também pode ser rodado à mão. */
class PurgeOutboxCommand extends Command
{
    protected $signature = 'outbox:purge';

    protected $description = 'Apaga de users_outbox os eventos processed mais velhos que OUTBOX_RETENTION_DAYS';

    public function handle(PurgeProcessedOutboxEvents $purge): int
    {
        try {
            $purged = $purge->execute();
        } catch (Throwable $e) {
            Log::error('outbox purge failed', ['error' => $e->getMessage()]);

            return self::FAILURE;
        }

        $this->line("{$purged} event(s) purged.");

        return self::SUCCESS;
    }
}

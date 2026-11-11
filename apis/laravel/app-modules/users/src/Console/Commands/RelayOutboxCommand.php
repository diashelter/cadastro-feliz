<?php

namespace Modules\Users\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;
use Modules\Users\UseCases\RelayOutboxEvents;
use Throwable;

/** O relay: agendado a cada segundo, só publica; o envio fica com quem consome o evento. */
class RelayOutboxCommand extends Command
{
    protected $signature = 'outbox:relay';

    protected $description = 'Publica na fila os eventos prontos de users_outbox';

    public function handle(RelayOutboxEvents $relay): int
    {
        try {
            $published = $relay->execute();
        } catch (Throwable $e) {
            Log::error('outbox relay failed', ['error' => $e->getMessage()]);

            return self::FAILURE;
        }

        $this->line("{$published} event(s) published.");

        return self::SUCCESS;
    }
}

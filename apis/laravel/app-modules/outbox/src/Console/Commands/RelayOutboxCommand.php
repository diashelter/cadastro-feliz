<?php

namespace Modules\Outbox\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Log;
use Modules\Outbox\Jobs\SendWelcomeEmailJob;
use Modules\Outbox\Repositories\OutboxRepository;
use Throwable;

/** O relay: agendado a cada segundo, só publica; o SMTP fica no job. */
class RelayOutboxCommand extends Command
{
    protected $signature = 'outbox:relay';

    protected $description = 'Publica na fila os eventos prontos de users_outbox';

    public function handle(OutboxRepository $events): int
    {
        try {
            $published = $events->publishReady(fn (string $id) => Bus::dispatch(new SendWelcomeEmailJob($id)));
        } catch (Throwable $e) {
            Log::error('outbox relay failed', ['error' => $e->getMessage()]);

            return self::FAILURE;
        }

        $this->line("{$published} event(s) published.");

        return self::SUCCESS;
    }
}

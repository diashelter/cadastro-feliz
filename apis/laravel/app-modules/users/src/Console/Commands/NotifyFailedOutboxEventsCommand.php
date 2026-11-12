<?php

namespace Modules\Users\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;
use Modules\Users\UseCases\NotifyFailedOutboxEvents;
use Throwable;

/** Agendado a cada 5 min: um resumo ao operador com os eventos failed ainda não avisados. */
class NotifyFailedOutboxEventsCommand extends Command
{
    protected $signature = 'outbox:notify-failed';

    protected $description = 'Envia a OUTBOX_ALERT_EMAIL um resumo dos eventos failed ainda não avisados';

    public function handle(NotifyFailedOutboxEvents $notify): int
    {
        try {
            $notified = $notify->execute();
        } catch (Throwable $e) {
            Log::error('outbox failed-events notification failed', ['error' => $e->getMessage()]);

            return self::FAILURE;
        }

        $this->line("{$notified} failed event(s) notified.");

        return self::SUCCESS;
    }
}

<?php

namespace Modules\Outbox\Jobs;

use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Modules\Outbox\Mail\WelcomeMail;
use Modules\Outbox\Repositories\OutboxRepository;
use Throwable;

/**
 * Carrega só o id do evento: nome e e-mail não passam pelo Redis (decisão 10). Roda uma
 * vez por mensagem, porque as retentativas ficam no banco (decisão 9). Sem transação
 * aberta durante o envio; só uma falha de envio conta como tentativa.
 */
class SendWelcomeEmailJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public function __construct(public string $eventId) {}

    public function handle(OutboxRepository $events): void
    {
        $event = $events->find($this->eventId);

        if ($event === null) {
            Log::warning('outbox event not found', ['event_id' => $this->eventId]);

            return;
        }

        if ($event->isTerminal()) {
            return;
        }

        try {
            Mail::to($event->payload['email'])->send(new WelcomeMail($event->payload['name'], $event->id));
        } catch (Throwable $e) {
            $events->recordFailure($event, $e->getMessage());

            return;
        }

        $events->markProcessed($event->id);
    }
}

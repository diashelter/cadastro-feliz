<?php

namespace Modules\Notifications\UseCases;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Modules\Notifications\Mail\WelcomeMail;
use Modules\Users\Repositories\OutboxRepository;
use Throwable;

/**
 * Envia o e-mail de boas-vindas de um evento user.registered e informa o resultado a users,
 * dono da tabela do outbox. Sem transação aberta durante o envio; só uma falha de envio conta
 * como tentativa.
 */
class SendWelcomeEmail
{
    public function __construct(private OutboxRepository $events) {}

    public function execute(string $eventId): void
    {
        $event = $this->events->find($eventId);

        if ($event === null) {
            Log::warning('outbox event not found', ['event_id' => $eventId]);

            return;
        }

        if ($event->isTerminal()) {
            return;
        }

        try {
            Mail::to($event->payload['email'])->send(new WelcomeMail($event->payload['name'], $event->id));
        } catch (Throwable $e) {
            $this->events->recordFailure($event, $e->getMessage());

            return;
        }

        $this->events->markProcessed($event->id);
    }
}

<?php

namespace Modules\Users\UseCases;

use Illuminate\Support\Facades\Mail;
use Modules\Users\Mail\FailedEventsDigestMail;
use Modules\Users\Repositories\OutboxRepository;

/**
 * Manda ao operador um resumo dos eventos failed ainda não avisados e só depois os marca. Sem
 * transação nem trava durante o envio: um resumo repetido é tolerado, um aviso perdido não.
 */
class NotifyFailedOutboxEvents
{
    public function __construct(private OutboxRepository $events) {}

    public function execute(): int
    {
        $failed = $this->events->unnotifiedFailures((int) config('outbox.batch_size'));

        if ($failed === []) {
            return 0;
        }

        Mail::to(config('outbox.alert_email'))->send(new FailedEventsDigestMail($failed));

        $this->events->markFailureNotified(array_map(fn (object $event) => $event->id, $failed));

        return count($failed);
    }
}

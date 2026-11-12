<?php

namespace Modules\Users\Jobs;

use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Modules\Users\UseCases\SendWelcomeEmail;

/**
 * Carrega só o id do evento: nome e e-mail não passam pelo Redis (decisão 10). Roda uma
 * vez por mensagem, porque as retentativas ficam no banco (decisão 9).
 */
class SendWelcomeEmailJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public function __construct(public string $eventId) {}

    public function handle(SendWelcomeEmail $send): void
    {
        $send->execute($this->eventId);
    }
}

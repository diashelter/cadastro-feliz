<?php

namespace Modules\Users\UseCases;

use Illuminate\Contracts\Bus\Dispatcher;
use Illuminate\Support\Facades\DB;
use Modules\Users\Enums\OutboxEventType;
use Modules\Users\Jobs\SendWelcomeEmailJob;
use Modules\Users\Repositories\OutboxRepository;
use ValueError;

/**
 * O relay: publica o lote pronto e só então o marca published, na mesma transação. Qualquer
 * falha desfaz o lote, e as mensagens que já saíram viram repetidas, que o consumidor tolera.
 * A publicação precisa ficar dentro da transação, com after_commit desligado na fila: fora
 * dela, a trava do lote some antes da publicação e duas execuções pegariam o mesmo evento.
 */
class RelayOutboxEvents
{
    public function __construct(
        private OutboxRepository $outbox,
        private Dispatcher $bus,
    ) {}

    /**
     * @return int quantos eventos foram publicados
     *
     * @throws ValueError quando um evento do lote tem um tipo fora de OutboxEventType; nada é publicado
     */
    public function execute(): int
    {
        return DB::transaction(function () {
            $batch = $this->outbox->lockReadyBatch();

            // Todos os jobs antes da primeira publicação: um tipo desconhecido desfaz o lote
            // sem ter publicado nada.
            $jobs = array_map(fn (object $event) => $this->jobFor($event->event_type, $event->id), $batch);

            foreach ($jobs as $job) {
                $this->bus->dispatch($job);
            }

            if ($batch !== []) {
                $this->outbox->markPublished(array_column($batch, 'id'));
            }

            return count($batch);
        });
    }

    private function jobFor(string $eventType, string $eventId): object
    {
        return match (OutboxEventType::from($eventType)) {
            OutboxEventType::UserRegistered => new SendWelcomeEmailJob($eventId),
        };
    }
}

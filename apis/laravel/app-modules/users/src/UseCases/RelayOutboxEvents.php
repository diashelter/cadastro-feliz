<?php

namespace Modules\Users\UseCases;

use Illuminate\Contracts\Bus\Dispatcher;
use Illuminate\Database\ConnectionInterface;
use Modules\Users\Exceptions\UnknownOutboxConsumer;
use Modules\Users\Repositories\OutboxRepository;
use Modules\Users\Services\OutboxConsumers;

/**
 * O relay: publica o lote pronto e só então o marca published, na mesma transação. Qualquer
 * falha desfaz o lote, e as mensagens que já saíram viram repetidas, que o consumidor tolera.
 * A publicação precisa ficar dentro da transação, com after_commit desligado na fila: fora
 * dela, a trava do lote some antes da publicação e duas execuções pegariam o mesmo evento.
 */
class RelayOutboxEvents
{
    public function __construct(
        private ConnectionInterface $db,
        private OutboxRepository $outbox,
        private OutboxConsumers $consumers,
        private Dispatcher $bus,
    ) {}

    /**
     * @return int quantos eventos foram publicados
     *
     * @throws UnknownOutboxConsumer quando um evento do lote não tem consumidor; nada é publicado
     */
    public function execute(): int
    {
        return $this->db->transaction(function () {
            $batch = $this->outbox->lockReadyBatch();

            // Todos os jobs antes da primeira publicação: um tipo sem consumidor desfaz o lote
            // sem ter publicado nada.
            $jobs = array_map(fn (object $event) => $this->consumers->jobFor($event->event_type, $event->id), $batch);

            foreach ($jobs as $job) {
                $this->bus->dispatch($job);
            }

            if ($batch !== []) {
                $this->outbox->markPublished(array_column($batch, 'id'));
            }

            return count($batch);
        });
    }
}

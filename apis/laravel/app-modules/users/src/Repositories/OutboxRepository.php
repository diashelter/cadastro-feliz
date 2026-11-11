<?php

namespace Modules\Users\Repositories;

use Illuminate\Support\Facades\DB;
use Modules\Users\Enums\OutboxEventType;
use Modules\Users\Enums\OutboxStatus;
use Modules\Users\Models\UserOutboxEvent;
use Modules\Users\Services\RetryPolicy;

/**
 * As consultas de docs/database.md. Só este módulo escreve em users_outbox, e nenhum método
 * abre transação: quem precisa de uma é o caso de uso que chama.
 */
class OutboxRepository
{
    /** Roda na transação de RegisterUser, junto do INSERT em users. */
    public function recordUserRegistered(string $userId, string $name, string $email, string $occurredAt): void
    {
        DB::insert(
            'insert into users_outbox (user_id, event_type, payload) values (?, ?, ?::jsonb)',
            [$userId, OutboxEventType::UserRegistered->value, json_encode(
                ['user_id' => $userId, 'name' => $name, 'email' => $email, 'occurred_at' => $occurredAt],
                JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE,
            )],
        );
    }

    /**
     * Trava o lote pronto até o fim da transação de quem chama. Duas execuções nunca pegam a
     * mesma linha: quem garante é o SKIP LOCKED, porque o cache da stack é array e o
     * withoutOverlapping só vale dentro de um processo.
     *
     * @return list<object{id: string, event_type: string}>
     */
    public function lockReadyBatch(): array
    {
        return DB::select(
            'select id, event_type from users_outbox
             where (status = ? and available_at <= now())
                or (status = ? and published_at <= now() - make_interval(secs => ?))
             order by created_at
             limit ?
             for update skip locked',
            [
                OutboxStatus::Pending->value,
                OutboxStatus::Published->value,
                (int) config('outbox.republish_after'),
                (int) config('outbox.batch_size'),
            ],
        );
    }

    /** @param  list<string>  $ids */
    public function markPublished(array $ids): void
    {
        DB::update(
            'update users_outbox set status = ?, published_at = now() where id = any(?::uuid[])',
            [OutboxStatus::Published->value, '{'.implode(',', $ids).'}'],
        );
    }

    public function find(string $id): ?UserOutboxEvent
    {
        return UserOutboxEvent::query()->find($id);
    }

    public function markProcessed(string $id): void
    {
        DB::update(
            'update users_outbox set status = ?, processed_at = now(), last_error = null where id = ?',
            [OutboxStatus::Processed->value, $id],
        );
    }

    public function recordFailure(UserOutboxEvent $event, string $error): void
    {
        DB::update(
            'update users_outbox
             set attempts = attempts + 1,
                 last_error = ?,
                 status = case when attempts + 1 >= ? then ? else ? end,
                 available_at = now() + make_interval(secs => ?)
             where id = ? and status not in (?, ?)',
            [
                $error,
                (int) config('outbox.max_attempts'),
                OutboxStatus::Failed->value,
                OutboxStatus::Pending->value,
                RetryPolicy::delaySeconds($event->attempts, (int) config('outbox.backoff_base')),
                $event->id,
                OutboxStatus::Processed->value,
                OutboxStatus::Failed->value,
            ],
        );
    }
}

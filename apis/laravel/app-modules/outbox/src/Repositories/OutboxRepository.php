<?php

namespace Modules\Outbox\Repositories;

use Illuminate\Support\Facades\DB;
use Modules\Outbox\Models\UserOutboxEvent;
use Modules\Outbox\Services\RetryPolicy;

/** As consultas de docs/database.md. */
class OutboxRepository
{
    /** Quem chama abre a transação, junto do INSERT em users. */
    public function recordUserRegistered(string $userId, string $name, string $email, string $occurredAt): void
    {
        DB::insert(
            "insert into users_outbox (user_id, event_type, payload) values (?, 'user.registered', ?::jsonb)",
            [$userId, json_encode(
                ['user_id' => $userId, 'name' => $name, 'email' => $email, 'occurred_at' => $occurredAt],
                JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE,
            )],
        );
    }

    /**
     * Publica o lote pronto e só então o marca published, na mesma transação: qualquer
     * falha desfaz o lote, e as mensagens que já saíram viram repetidas, que o job tolera.
     * Duas execuções nunca pegam a mesma linha: quem garante é o SKIP LOCKED, porque o cache
     * da stack é array e o withoutOverlapping só vale dentro de um processo.
     *
     * @param  callable(string): void  $publish
     */
    public function publishReady(callable $publish): int
    {
        return DB::transaction(function () use ($publish) {
            $ids = array_column(DB::select(
                "select id from users_outbox
                 where (status = 'pending' and available_at <= now())
                    or (status = 'published' and published_at <= now() - make_interval(secs => ?))
                 order by created_at
                 limit ?
                 for update skip locked",
                [(int) config('outbox.republish_after'), (int) config('outbox.batch_size')],
            ), 'id');

            foreach ($ids as $id) {
                $publish($id);
            }

            if ($ids !== []) {
                DB::update(
                    "update users_outbox set status = 'published', published_at = now() where id = any(?::uuid[])",
                    ['{'.implode(',', $ids).'}'],
                );
            }

            return count($ids);
        });
    }

    public function find(string $id): ?UserOutboxEvent
    {
        return UserOutboxEvent::query()->find($id);
    }

    public function markProcessed(string $id): void
    {
        DB::update(
            "update users_outbox set status = 'processed', processed_at = now(), last_error = null where id = ?",
            [$id],
        );
    }

    public function recordFailure(UserOutboxEvent $event, string $error): void
    {
        DB::update(
            "update users_outbox
             set attempts = attempts + 1,
                 last_error = ?,
                 status = case when attempts + 1 >= ? then 'failed' else 'pending' end,
                 available_at = now() + make_interval(secs => ?)
             where id = ? and status not in ('processed', 'failed')",
            [
                $error,
                (int) config('outbox.max_attempts'),
                RetryPolicy::delaySeconds($event->attempts, (int) config('outbox.backoff_base')),
                $event->id,
            ],
        );
    }
}

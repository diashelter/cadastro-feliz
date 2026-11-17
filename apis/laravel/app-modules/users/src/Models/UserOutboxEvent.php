<?php

namespace Modules\Users\Models;

use Illuminate\Database\Eloquent\Attributes\Table;
use Illuminate\Database\Eloquent\Model;
use Modules\Users\Enums\OutboxEventType;
use Modules\Users\Enums\OutboxStatus;

/**
 * Uma linha de users_outbox. O ciclo de status está em docs/database.md.
 *
 * @property OutboxStatus $status
 * @property OutboxEventType $event_type
 */
#[Table('users_outbox', keyType: 'string', incrementing: false, timestamps: false)]
class UserOutboxEvent extends Model
{
    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'attempts' => 'integer',
            'status' => OutboxStatus::class,
            'event_type' => OutboxEventType::class,
        ];
    }

    public function isTerminal(): bool
    {
        return $this->status->isTerminal();
    }
}

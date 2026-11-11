<?php

namespace Modules\Users\Models;

use Illuminate\Database\Eloquent\Model;
use Modules\Users\Enums\OutboxEventType;
use Modules\Users\Enums\OutboxStatus;

/**
 * Uma linha de users_outbox. O ciclo de status está em docs/database.md.
 *
 * @property OutboxStatus $status
 * @property OutboxEventType $event_type
 */
class UserOutboxEvent extends Model
{
    public $incrementing = false;

    public $timestamps = false;

    protected $table = 'users_outbox';

    protected $keyType = 'string';

    protected $casts = [
        'payload' => 'array',
        'attempts' => 'integer',
        'status' => OutboxStatus::class,
        'event_type' => OutboxEventType::class,
    ];

    public function isTerminal(): bool
    {
        return $this->status->isTerminal();
    }
}

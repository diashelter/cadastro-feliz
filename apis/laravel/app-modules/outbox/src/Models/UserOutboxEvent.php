<?php

namespace Modules\Outbox\Models;

use Illuminate\Database\Eloquent\Model;

/** Uma linha de users_outbox. O ciclo de status está em docs/database.md. */
class UserOutboxEvent extends Model
{
    public const array TERMINAL_STATUSES = ['processed', 'failed'];

    public $incrementing = false;

    public $timestamps = false;

    protected $table = 'users_outbox';

    protected $keyType = 'string';

    protected $casts = ['payload' => 'array', 'attempts' => 'integer'];

    public function isTerminal(): bool
    {
        return in_array($this->status, self::TERMINAL_STATUSES, true);
    }
}

<?php

namespace Modules\Users\Enums;

/** O event_type de users_outbox. O valor é o mesmo nas três stacks (docs/database.md). */
enum OutboxEventType: string
{
    case UserRegistered = 'user.registered';
}

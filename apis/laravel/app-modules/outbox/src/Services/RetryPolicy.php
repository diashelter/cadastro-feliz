<?php

namespace Modules\Outbox\Services;

/** A espera antes de uma nova tentativa de envio (decisão 9 de docs/decisions.md). */
class RetryPolicy
{
    public static function delaySeconds(int $previousAttempts, int $base): int
    {
        return $base * 2 ** $previousAttempts;
    }
}

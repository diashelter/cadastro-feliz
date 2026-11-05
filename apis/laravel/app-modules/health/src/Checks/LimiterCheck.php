<?php

namespace Modules\Health\Checks;

use Illuminate\Support\Facades\Redis;
use RuntimeException;

/**
 * Um PING ao redis-limiter pela conexão `limiter`, que desiste em 1 s
 * (timeout e read_timeout em config/database.php).
 */
class LimiterCheck implements HealthCheck
{
    public function name(): string
    {
        return 'limiter';
    }

    public function run(): void
    {
        $reply = Redis::connection('limiter')->ping();

        if ($reply !== true && $reply !== '+PONG' && $reply !== 'PONG') {
            throw new RuntimeException('unexpected PING reply');
        }
    }
}

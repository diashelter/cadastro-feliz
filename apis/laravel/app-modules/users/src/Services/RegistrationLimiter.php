<?php

namespace Modules\Users\Services;

use Illuminate\Support\Facades\Redis;
use Modules\Users\Exceptions\RegistrationLimited;

/**
 * Roda os scripts do contrato no redis-limiter. Os limites nativos do framework não
 * servem: gravam com chave e formato próprios, e o contador é comum às três stacks.
 */
class RegistrationLimiter
{
    /** @throws RegistrationLimited */
    public function countAttempt(string $ip, string $email): void
    {
        [$attempts, $ttl] = $this->run(
            'attempts',
            RegistrationKeys::attempts($ip, $email),
            (int) config('registration.attempt_window'),
        );

        if ($attempts > (int) config('registration.max_attempts')) {
            throw new RegistrationLimited(max(1, (int) $ttl));
        }
    }

    /** @throws RegistrationLimited */
    public function reserveQuota(string $ip): void
    {
        [$reserved, $ttl] = $this->run(
            'reserve',
            RegistrationKeys::quota($ip),
            (int) config('registration.max_per_ip'),
            (int) config('registration.ip_window'),
        );

        if ((int) $reserved === 0) {
            throw new RegistrationLimited((int) $ttl);
        }
    }

    public function releaseQuota(string $ip): void
    {
        $this->run('release', RegistrationKeys::quota($ip));
    }

    private function run(string $script, string $key, int ...$arguments): mixed
    {
        $source = (string) file_get_contents(dirname(__DIR__, 2)."/resources/lua/{$script}.lua");

        return Redis::connection('limiter')->eval($source, 1, $key, ...$arguments);
    }
}

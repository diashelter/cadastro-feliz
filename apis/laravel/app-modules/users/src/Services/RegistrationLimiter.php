<?php

namespace Modules\Users\Services;

use Illuminate\Cache\RateLimiter;
use Illuminate\Contracts\Cache\Factory as CacheFactory;
use Modules\Users\Exceptions\RegistrationLimited;

/**
 * O contador de tentativas e a cota por IP no redis-limiter, pelo RateLimiter do framework sobre
 * o cache store `limiter`. O formato das chaves é desta stack (decisão 28).
 *
 * Cada operação incrementa e compara o valor devolvido, que é atômico no Redis: verificar antes
 * e incrementar depois deixaria requisições paralelas passarem juntas. A cota recusada desfaz o
 * próprio incremento, e um decremento que fica abaixo de zero, porque a janela expirou no meio,
 * é desfeito também.
 */
class RegistrationLimiter
{
    private RateLimiter $limits;

    public function __construct(CacheFactory $cache)
    {
        $this->limits = new RateLimiter($cache->store('limiter'));
    }

    /** @throws RegistrationLimited */
    public function countAttempt(string $ip, string $email): void
    {
        $key = RegistrationKeys::attempts($ip, $email);
        $attempts = $this->limits->increment($key, (int) config('registration.attempt_window'));

        if ($attempts > (int) config('registration.max_attempts')) {
            throw new RegistrationLimited($this->secondsLeft($key));
        }
    }

    /** @throws RegistrationLimited */
    public function reserveQuota(string $ip): void
    {
        $key = RegistrationKeys::quota($ip);
        $used = $this->limits->increment($key, $this->ipWindow());

        if ($used > (int) config('registration.max_per_ip')) {
            $retryAfter = $this->secondsLeft($key);
            $this->decrement($key);

            throw new RegistrationLimited($retryAfter);
        }
    }

    public function releaseQuota(string $ip): void
    {
        $this->decrement(RegistrationKeys::quota($ip));
    }

    /** O RateLimiter recria com expiração uma chave que expirou; abaixo de zero, a unidade volta. */
    private function decrement(string $key): void
    {
        if ($this->limits->decrement($key, $this->ipWindow()) < 0) {
            $this->limits->increment($key, $this->ipWindow());
        }
    }

    /** No último segundo da janela o resto arredonda para 0, e `Retry-After: 0` mandaria tentar antes da hora. */
    private function secondsLeft(string $key): int
    {
        return max(1, $this->limits->availableIn($key));
    }

    private function ipWindow(): int
    {
        return (int) config('registration.ip_window');
    }
}

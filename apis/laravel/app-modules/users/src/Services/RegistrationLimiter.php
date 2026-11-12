<?php

namespace Modules\Users\Services;

use Illuminate\Contracts\Redis\Factory as RedisFactory;
use Modules\Users\Exceptions\RegistrationLimited;
use RuntimeException;

/**
 * O contador de tentativas e a cota por IP no redis-limiter, com comandos Redis na conexão
 * `limiter`. O formato das chaves é desta stack (decisão 28).
 *
 * Cada operação incrementa e compara o valor devolvido: verificar antes e incrementar depois
 * deixaria requisições paralelas passarem juntas. O incremento e a expiração vão na mesma
 * transação, e `EXPIRE ... NX` só define a expiração de uma chave que ainda não tem, então
 * nenhum contador fica sem expiração e a janela é fixa. O `RateLimiter` do framework não serve:
 * o `increment` dele roda em passos separados e o último sobrescreve um incremento concorrente.
 * A cota recusada desfaz o próprio incremento, e um decremento que fica abaixo de zero, porque a
 * janela expirou no meio, é desfeito também.
 */
class RegistrationLimiter
{
    /** A conexão é aberta na primeira operação, dentro do try do controller: o phpredis conecta ao criá-la. */
    public function __construct(private RedisFactory $redis) {}

    /** @throws RegistrationLimited */
    public function countAttempt(string $ip, string $email): void
    {
        [$attempts, $ttl] = $this->change(
            RegistrationKeys::attempts($ip, $email),
            1,
            (int) config('registration.attempt_window'),
        );

        if ($attempts > (int) config('registration.max_attempts')) {
            throw new RegistrationLimited($this->secondsLeft($ttl));
        }
    }

    /** @throws RegistrationLimited */
    public function reserveQuota(string $ip): void
    {
        $key = RegistrationKeys::quota($ip);
        [$used, $ttl] = $this->change($key, 1, $this->ipWindow());

        if ($used > (int) config('registration.max_per_ip')) {
            $this->decrement($key);

            throw new RegistrationLimited($this->secondsLeft($ttl));
        }
    }

    public function releaseQuota(string $ip): void
    {
        $this->decrement(RegistrationKeys::quota($ip));
    }

    private function decrement(string $key): void
    {
        [$value] = $this->change($key, -1, $this->ipWindow());

        if ($value < 0) {
            $this->change($key, 1, $this->ipWindow());
        }
    }

    /**
     * Soma $by à chave e garante a expiração, numa só transação.
     *
     * @return array{int, int} o valor novo e os segundos restantes
     */
    private function change(string $key, int $by, int $window): array
    {
        // O cliente direto, sem o transaction() do Laravel: ele reconecta e roda um DISCARD numa
        // falha, e com o redis-limiter fora do ar cada tentativa espera o timeout de 1 s.
        $results = $this->redis->connection('limiter')->client()->multi()
            ->incrBy($key, $by)
            ->expire($key, $window, 'NX')
            ->ttl($key)
            ->exec();

        // O EXPIRE com NX devolve false quando a chave já tem expiração; só o INCRBY e o TTL contam.
        if (! is_array($results) || ! is_int($results[0] ?? null) || ! is_int($results[2] ?? null)) {
            throw new RuntimeException('redis-limiter transaction failed');
        }

        return [(int) $results[0], (int) $results[2]];
    }

    /** No último meio segundo da janela o `TTL` arredonda para 0, e `Retry-After: 0` mandaria tentar antes da hora. */
    private function secondsLeft(int $ttl): int
    {
        return max(1, $ttl);
    }

    private function ipWindow(): int
    {
        return (int) config('registration.ip_window');
    }
}

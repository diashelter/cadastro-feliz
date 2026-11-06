<?php

namespace Modules\Users\Actions;

use Illuminate\Support\Facades\Log;
use Modules\Users\Exceptions\RegistrationLimited;
use Modules\Users\Models\User;
use Modules\Users\Repositories\UserRepository;
use Modules\Users\Services\RegistrationLimiter;
use Throwable;

/**
 * A ordem de processamento do contrato. Este caminho não toca na fila: o relay publica
 * o evento que o UserRepository grava na transação do cadastro.
 */
class RegisterUserAction
{
    public function __construct(
        private RegistrationLimiter $limiter,
        private UserRepository $users,
    ) {}

    /** @throws RegistrationLimited */
    public function __invoke(string $name, string $email, string $ip): User
    {
        $email = mb_strtolower(trim($email));

        $this->limiter->countAttempt($ip, $email);
        $this->limiter->reserveQuota($ip);

        try {
            return $this->users->create(trim($name), $email);
        } catch (Throwable $e) {
            $this->releaseQuota($ip);

            throw $e;
        }
    }

    private function releaseQuota(string $ip): void
    {
        try {
            $this->limiter->releaseQuota($ip);
        } catch (Throwable $e) {
            Log::error('registration quota not released', ['error' => $e->getMessage()]);
        }
    }
}

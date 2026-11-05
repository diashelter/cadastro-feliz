<?php

namespace Modules\Users\Actions;

use Illuminate\Support\Facades\Log;
use Modules\Users\Exceptions\RegistrationLimited;
use Modules\Users\Models\User;
use Modules\Users\Repositories\UserRepository;
use Modules\Users\Services\RegistrationLimiter;
use Modules\Users\Services\WelcomeEmailPublisher;
use Throwable;

/**
 * A ordem de processamento do contrato. Gravar o usuário e publicar o job são duas
 * escritas sem transação comum, de propósito: é a limitação que o outbox vai corrigir
 * (decisão 21).
 */
class RegisterUserAction
{
    public function __construct(
        private RegistrationLimiter $limiter,
        private UserRepository $users,
        private WelcomeEmailPublisher $publisher,
    ) {}

    /** @throws RegistrationLimited */
    public function __invoke(string $name, string $email, string $ip): User
    {
        $email = mb_strtolower(trim($email));

        $this->limiter->countAttempt($ip, $email);
        $this->limiter->reserveQuota($ip);

        try {
            $user = $this->users->create(trim($name), $email);
        } catch (Throwable $e) {
            $this->releaseQuota($ip);

            throw $e;
        }

        $this->publisher->publish($user);

        return $user;
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

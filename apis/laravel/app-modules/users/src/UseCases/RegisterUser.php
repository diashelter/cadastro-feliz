<?php

namespace Modules\Users\UseCases;

use Illuminate\Database\ConnectionInterface;
use Illuminate\Support\Facades\Log;
use Modules\Users\Exceptions\EmailAlreadyTaken;
use Modules\Users\Exceptions\RegistrationLimited;
use Modules\Users\Models\User;
use Modules\Users\Repositories\OutboxRepository;
use Modules\Users\Repositories\UserRepository;
use Modules\Users\Services\RegistrationLimiter;
use Throwable;

/**
 * POST /users, na ordem do contrato. Usuário e evento são gravados na mesma transação, ou
 * nenhum dos dois (decisão 1). Este caminho não toca na fila: quem publica é o relay.
 */
class RegisterUser
{
    public function __construct(
        private ConnectionInterface $db,
        private RegistrationLimiter $limiter,
        private UserRepository $users,
        private OutboxRepository $outbox,
    ) {}

    /**
     * @throws RegistrationLimited
     * @throws EmailAlreadyTaken
     */
    public function execute(string $name, string $email, string $ip): User
    {
        $email = mb_strtolower(trim($email));

        $this->limiter->countAttempt($ip, $email);
        $this->limiter->reserveQuota($ip);

        try {
            return $this->db->transaction(function () use ($name, $email) {
                $user = $this->users->create(trim($name), $email);

                $this->outbox->recordUserRegistered(
                    $user->id,
                    $user->name,
                    $user->email,
                    $user->created_at->copy()->utc()->format('Y-m-d\TH:i:s\Z'),
                );

                return $user;
            });
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

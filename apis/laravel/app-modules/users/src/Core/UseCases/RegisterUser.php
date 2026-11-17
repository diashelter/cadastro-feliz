<?php

namespace Modules\Users\Core\UseCases;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Modules\Users\Core\Dtos\RegisterUserDto;
use Modules\Users\Core\Exceptions\EmailAlreadyTaken;
use Modules\Users\Core\Exceptions\RegistrationLimited;
use Modules\Users\Core\Services\RegistrationLimiter;
use Modules\Users\Persistence\Models\User;
use Modules\Users\Persistence\Repositories\OutboxRepository;
use Modules\Users\Persistence\Repositories\UserRepository;
use Throwable;

/**
 * POST /users, na ordem do contrato, a partir dos dados já normalizados pelo StoreUserRequest.
 * Usuário e evento são gravados na mesma transação, ou nenhum dos dois (decisão 1). Este
 * caminho não toca na fila: quem publica é o relay.
 */
class RegisterUser
{
    public function __construct(
        private RegistrationLimiter $limiter,
        private UserRepository $users,
        private OutboxRepository $outbox,
    ) {}

    /**
     * @throws RegistrationLimited
     * @throws EmailAlreadyTaken
     */
    public function execute(RegisterUserDto $data, string $ip): User
    {
        $this->limiter->countAttempt($ip, $data->email);
        $this->limiter->reserveQuota($ip);

        try {
            return DB::transaction(function () use ($data) {
                $user = $this->users->create($data->name, $data->email);

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

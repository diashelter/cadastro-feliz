<?php

namespace Modules\Users\Repositories;

use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use Modules\Outbox\Repositories\OutboxRepository;
use Modules\Users\Exceptions\EmailAlreadyTaken;
use Modules\Users\Models\User;

class UserRepository
{
    public function __construct(private OutboxRepository $outbox) {}

    /**
     * Usuário e evento são gravados juntos ou nenhum dos dois (decisão 1). Sem SELECT
     * prévio: a constraint UNIQUE detecta o e-mail repetido e também resolve duas
     * requisições simultâneas.
     *
     * @throws EmailAlreadyTaken
     */
    public function create(string $name, string $email): User
    {
        try {
            return DB::transaction(function () use ($name, $email) {
                $row = DB::selectOne(
                    'insert into users (name, email) values (?, ?) returning id, name, email, created_at, updated_at',
                    [$name, $email],
                );
                $user = (new User)->newFromBuilder($row);

                $this->outbox->recordUserRegistered(
                    $user->id,
                    $user->name,
                    $user->email,
                    $user->created_at->copy()->utc()->format('Y-m-d\TH:i:s\Z'),
                );

                return $user;
            });
        } catch (UniqueConstraintViolationException) {
            throw new EmailAlreadyTaken;
        }
    }
}

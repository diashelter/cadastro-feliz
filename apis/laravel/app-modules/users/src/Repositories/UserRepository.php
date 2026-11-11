<?php

namespace Modules\Users\Repositories;

use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use Modules\Users\Exceptions\EmailAlreadyTaken;
use Modules\Users\Models\User;

class UserRepository
{
    /**
     * Roda na transação de RegisterUser. Sem SELECT prévio: a constraint UNIQUE detecta o
     * e-mail repetido e também resolve duas requisições simultâneas.
     *
     * @throws EmailAlreadyTaken
     */
    public function create(string $name, string $email): User
    {
        try {
            $row = DB::selectOne(
                'insert into users (name, email) values (?, ?) returning id, name, email, created_at, updated_at',
                [$name, $email],
            );
        } catch (UniqueConstraintViolationException) {
            throw new EmailAlreadyTaken;
        }

        return (new User)->newFromBuilder($row);
    }
}

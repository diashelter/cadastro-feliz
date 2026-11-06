<?php

namespace App\Database;

use Illuminate\Database\Connectors\PostgresConnector;
use Throwable;

/**
 * O Laravel trata um nome que não resolve como conexão perdida e tenta de novo, o que
 * dobra o tempo de um banco fora do ar. Aqui a falha sobe na primeira tentativa, para
 * GET /health e POST /users cumprirem o limite de 3 s do contrato.
 */
class FailFastPostgresConnector extends PostgresConnector
{
    protected function tryAgainIfCausedByLostConnection(Throwable $e, $dsn, $username, #[\SensitiveParameter] $password, $options)
    {
        throw $e;
    }
}

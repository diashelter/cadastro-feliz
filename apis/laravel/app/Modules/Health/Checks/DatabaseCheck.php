<?php

namespace App\Modules\Health\Checks;

use Illuminate\Support\Facades\DB;

/**
 * Uma consulta sem tabela ao PostgreSQL, pela conexão padrão. A conexão desiste
 * em 1 s (PDO::ATTR_TIMEOUT em config/database.php), e é aberta antes da consulta
 * porque o Laravel repete uma consulta que falha ao conectar, o que dobraria o tempo.
 */
class DatabaseCheck implements HealthCheck
{
    public function name(): string
    {
        return 'database';
    }

    public function run(): void
    {
        $connection = DB::connection();
        $connection->getPdo();
        $connection->select('select 1');
    }
}

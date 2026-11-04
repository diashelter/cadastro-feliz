<?php

namespace App\Modules\Health\Checks;

use Illuminate\Support\Facades\DB;

/**
 * Uma consulta sem tabela ao PostgreSQL, pela conexão padrão. A conexão desiste
 * em 1 s (PDO::ATTR_TIMEOUT em config/database.php).
 */
class DatabaseCheck implements HealthCheck
{
    public function name(): string
    {
        return 'database';
    }

    public function run(): void
    {
        DB::connection()->select('select 1');
    }
}

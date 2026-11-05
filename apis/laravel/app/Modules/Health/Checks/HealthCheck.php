<?php

namespace App\Modules\Health\Checks;

/**
 * Uma dependência que GET /health consulta. Falha lançando qualquer Throwable.
 */
interface HealthCheck
{
    /** Nome do check no corpo de /health. */
    public function name(): string;

    public function run(): void;
}

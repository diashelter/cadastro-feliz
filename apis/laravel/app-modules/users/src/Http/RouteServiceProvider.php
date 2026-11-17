<?php

namespace Modules\Users\Http;

use Illuminate\Support\ServiceProvider;

// As rotas do módulo ficam na camada Http, fora de routes/, onde o internachi/modular as
// procuraria; por isso o módulo as carrega com um provider próprio, descoberto pelo composer.json.
class RouteServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        $this->loadRoutesFrom(__DIR__.'/routes.php');
    }
}

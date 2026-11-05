<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Bootstrap\LoadEnvironmentVariables;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

// As rotas da API ficam nos módulos, em app-modules, na raiz e sem a rota nativa /up:
// o endpoint de saúde é GET /health (docs/api-contract.md).
$app = Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        commands: __DIR__.'/../routes/console.php',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        //
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Todo erro sai em JSON, mesmo sem o header Accept (docs/stacks.md › Laravel).
        $exceptions->shouldRenderJsonWhen(fn () => true);
    })->create();

// apis/laravel não tem .env: as variáveis vêm do .env da raiz, pelo container. Sem o
// arquivo, o Laravel nem tenta lê-lo (a leitura que falha vira aviso em `artisan test`).
if (! is_file($app->environmentFilePath())) {
    $app->bind(LoadEnvironmentVariables::class, fn () => new class
    {
        public function bootstrap(): void {}
    });
}

return $app;

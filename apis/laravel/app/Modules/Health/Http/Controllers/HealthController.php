<?php

namespace App\Modules\Health\Http\Controllers;

use App\Modules\Health\Checks\DatabaseCheck;
use App\Modules\Health\Checks\HealthCheck;
use App\Modules\Health\Checks\LimiterCheck;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;
use Throwable;

/**
 * GET /health, contrato comum às três stacks (docs/api-contract.md › GET /health).
 * O motivo de uma falha vai para o log, nunca para o corpo.
 */
class HealthController
{
    public function __invoke(DatabaseCheck $database, LimiterCheck $limiter): JsonResponse
    {
        $checks = [];

        foreach ([$database, $limiter] as $check) {
            $checks[$check->name()] = $this->run($check);
        }

        $healthy = ! in_array('fail', $checks, true);

        return response()->json(
            ['status' => $healthy ? 'ok' : 'fail', 'checks' => $checks],
            $healthy ? 200 : 503,
            ['Cache-Control' => 'no-store'],
        );
    }

    private function run(HealthCheck $check): string
    {
        try {
            $check->run();

            return 'ok';
        } catch (Throwable $e) {
            Log::error("health check {$check->name()} failed", ['error' => $e->getMessage()]);

            return 'fail';
        }
    }
}

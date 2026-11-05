<?php

namespace Modules\Users\Services;

use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Log;
use Modules\Users\Jobs\SendWelcomeEmailJob;
use Modules\Users\Models\User;
use Throwable;

/**
 * O único ponto que publica o job, e a porta que a rodada do outbox substitui. Uma
 * publicação que falha não muda a resposta: o usuário fica gravado e o e-mail se perde,
 * e essa perda é o que esta rodada existe para mostrar (decisão 21).
 */
class WelcomeEmailPublisher
{
    public function publish(User $user): void
    {
        try {
            Bus::dispatch(new SendWelcomeEmailJob($user->id));
        } catch (Throwable $e) {
            Log::error('SendWelcomeEmailJob not published', ['user_id' => $user->id, 'error' => $e->getMessage()]);
        }
    }
}

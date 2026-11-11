<?php

namespace Modules\Notifications\Providers;

use Illuminate\Support\ServiceProvider;
use Modules\Notifications\Jobs\SendWelcomeEmailJob;
use Modules\Users\Enums\OutboxEventType;
use Modules\Users\Services\OutboxConsumers;

/** Registra notifications como consumidor de user.registered: users nunca conhece este módulo. */
class NotificationsServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        $this->app->make(OutboxConsumers::class)->register(
            OutboxEventType::UserRegistered,
            fn (string $eventId) => new SendWelcomeEmailJob($eventId),
        );
    }
}

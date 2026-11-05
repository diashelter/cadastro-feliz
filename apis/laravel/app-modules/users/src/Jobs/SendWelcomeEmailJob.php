<?php

namespace Modules\Users\Jobs;

use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Mail;
use Modules\Users\Mail\WelcomeMail;
use Modules\Users\Models\User;

/**
 * Carrega só o id: nome e e-mail não passam pelo Redis (decisão 10). As retentativas são
 * as nativas do Horizon, com os mesmos valores do outbox (decisão 21).
 */
class SendWelcomeEmailJob implements ShouldQueue
{
    use Queueable;

    public function __construct(public string $userId) {}

    public function tries(): int
    {
        return (int) config('registration.mail_max_attempts');
    }

    /** @return list<int> */
    public function backoff(): array
    {
        $base = (int) config('registration.mail_backoff_base');

        return array_map(fn (int $failure) => $base * 2 ** $failure, range(0, max(0, $this->tries() - 2)));
    }

    public function handle(): void
    {
        $user = User::query()->findOrFail($this->userId);

        Mail::to($user->email)->send(new WelcomeMail($user->name));
    }
}

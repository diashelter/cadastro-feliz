<?php

use Modules\Outbox\Jobs\SendWelcomeEmailJob;
use Modules\Outbox\Mail\WelcomeMail;
use Modules\Outbox\Services\RetryPolicy;

it('waits base times two to the previous attempts', function () {
    expect(array_map(fn (int $previous) => RetryPolicy::delaySeconds($previous, 30), [0, 1, 2, 3]))
        ->toBe([30, 60, 120, 240])
        ->and(RetryPolicy::delaySeconds(0, 2))->toBe(2);
});

it('runs once with no native backoff', function () {
    $job = new SendWelcomeEmailJob('0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e');

    expect($job->tries)->toBe(1)
        ->and(property_exists($job, 'backoff'))->toBeFalse()
        ->and(method_exists($job, 'backoff'))->toBeFalse();
});

it('derives the message id from the event', function () {
    $mail = new WelcomeMail('Ana', '0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e');

    expect($mail->headers()->messageId)->toBe('0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e@cadastro-feliz.local');
});

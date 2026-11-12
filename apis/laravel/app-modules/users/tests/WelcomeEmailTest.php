<?php

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Modules\Users\Jobs\SendWelcomeEmailJob;
use Modules\Users\Mail\WelcomeMail;
use Modules\Users\Repositories\OutboxRepository;
use Modules\Users\UseCases\SendWelcomeEmail;

const WELCOME_EVENT_ID = '0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e';

function welcomeEvent(string $status): Modules\Users\Models\UserOutboxEvent
{
    return (new Modules\Users\Models\UserOutboxEvent)->newFromBuilder((object) [
        'id' => WELCOME_EVENT_ID,
        'event_type' => 'user.registered',
        'payload' => json_encode(['user_id' => 'u1', 'name' => 'Ana Souza', 'email' => 'ana@example.com', 'occurred_at' => '2026-11-04T12:00:00Z']),
        'status' => $status,
        'attempts' => 0,
    ]);
}

it('runs once with no native backoff', function () {
    $job = new SendWelcomeEmailJob(WELCOME_EVENT_ID);

    expect($job->tries)->toBe(1)
        ->and(property_exists($job, 'backoff'))->toBeFalse()
        ->and(method_exists($job, 'backoff'))->toBeFalse();
});

it('derives the message id from the event', function () {
    $mail = new WelcomeMail('Ana', WELCOME_EVENT_ID);

    expect($mail->headers()->messageId)->toBe(WELCOME_EVENT_ID.'@cadastro-feliz.local');
});

it('renders the users views', function () {
    $content = (new WelcomeMail('Ana', WELCOME_EVENT_ID))->content();

    expect($content->html)->toBe('users::welcome')
        ->and($content->text)->toBe('users::welcome-text')
        ->and((new WelcomeMail('Ana', WELCOME_EVENT_ID))->render())->toContain('Olá, Ana!');
});

it('skips terminal events', function () {
    foreach (['processed', 'failed'] as $status) {
        Mail::fake();
        $events = Mockery::mock(OutboxRepository::class);
        $events->shouldReceive('find')->once()->with(WELCOME_EVENT_ID)->andReturn(welcomeEvent($status));
        $events->shouldNotReceive('markProcessed', 'recordFailure');

        (new SendWelcomeEmail($events))->execute(WELCOME_EVENT_ID);

        Mail::assertNothingSent();
    }
});

it('sends the welcome mail and marks the event processed', function () {
    foreach (['pending', 'published'] as $status) {
        Mail::fake();
        $events = Mockery::mock(OutboxRepository::class);
        $events->shouldReceive('find')->once()->andReturn(welcomeEvent($status));
        $events->shouldReceive('markProcessed')->once()->with(WELCOME_EVENT_ID);
        $events->shouldNotReceive('recordFailure');

        (new SendWelcomeEmail($events))->execute(WELCOME_EVENT_ID);

        Mail::assertSent(WelcomeMail::class, fn (WelcomeMail $mail) => $mail->hasTo('ana@example.com')
            && $mail->name === 'Ana Souza' && $mail->eventId === WELCOME_EVENT_ID);
        Mail::assertSentCount(1);
    }
});

it('records the send failure and does not mark processed', function () {
    Mail::shouldReceive('to')->once()->with('ana@example.com')->andThrow(new RuntimeException('boom'));
    $event = welcomeEvent('published');
    $events = Mockery::mock(OutboxRepository::class);
    $events->shouldReceive('find')->once()->andReturn($event);
    $events->shouldReceive('recordFailure')->once()->with($event, 'boom');
    $events->shouldNotReceive('markProcessed');

    (new SendWelcomeEmail($events))->execute(WELCOME_EVENT_ID);
});

it('warns and sends nothing for a missing event', function () {
    Mail::fake();
    Log::shouldReceive('warning')->once()->with('outbox event not found', ['event_id' => WELCOME_EVENT_ID]);
    $events = Mockery::mock(OutboxRepository::class);
    $events->shouldReceive('find')->once()->andReturn(null);
    $events->shouldNotReceive('markProcessed', 'recordFailure');

    (new SendWelcomeEmail($events))->execute(WELCOME_EVENT_ID);

    Mail::assertNothingSent();
});

<?php

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Modules\Users\Mail\FailedEventsDigestMail;
use Modules\Users\Repositories\OutboxRepository;
use Modules\Users\UseCases\NotifyFailedOutboxEvents;
use Modules\Users\UseCases\PurgeProcessedOutboxEvents;

/** Uma linha de unnotifiedFailures. */
function failedEvent(string $id, string $email, int $attempts = 5, ?string $error = 'Connection refused'): object
{
    return (object) ['id' => $id, 'email' => $email, 'attempts' => $attempts, 'last_error' => $error];
}

// --- outbox:purge ---

it('prints the purged count', function () {
    $this->mock(PurgeProcessedOutboxEvents::class)->shouldReceive('execute')->once()->andReturn(3);

    $this->artisan('outbox:purge')->expectsOutput('3 event(s) purged.')->assertExitCode(0);
});

it('exits 1 and logs when the purge fails', function () {
    $this->mock(PurgeProcessedOutboxEvents::class)->shouldReceive('execute')->once()
        ->andThrow(new RuntimeException('purge boom'));
    Log::shouldReceive('error')->once()
        ->with('outbox purge failed', Mockery::on(fn (array $context) => str_contains($context['error'], 'purge boom')));

    $this->artisan('outbox:purge')->assertExitCode(1);
});

it('purges with the configured retention days', function () {
    config(['outbox.retention_days' => 7]);
    $events = Mockery::mock(OutboxRepository::class);
    $events->shouldReceive('purgeProcessedOlderThan')->once()->with(7)->andReturn(2);

    expect((new PurgeProcessedOutboxEvents($events))->execute())->toBe(2);
});

it('refuses a retention below one day', function () {
    foreach ([0, -1] as $days) {
        config(['outbox.retention_days' => $days]);
        $events = Mockery::mock(OutboxRepository::class);
        $events->shouldNotReceive('purgeProcessedOlderThan');

        expect(fn () => (new PurgeProcessedOutboxEvents($events))->execute())
            ->toThrow(InvalidArgumentException::class);
    }
});

// --- outbox:notify-failed ---

it('renders the digest subject, lines and footer', function () {
    $mail = new FailedEventsDigestMail([
        failedEvent('e1', 'ana@example.com', 5, 'Connection refused'),
        failedEvent('e2', 'bia@example.com', 3, "line one\n  line two"),
    ]);

    expect($mail->envelope()->subject)->toBe('Cadastro Feliz: 2 evento(s) sem envio')
        ->and($mail->content()->text)->toBe('users::failed-events-digest-text')
        ->and($mail->content()->html)->toBeNull()
        ->and(trim($mail->render()))->toBe(implode("\n", [
            '- e1 · ana@example.com · 5 tentativa(s) · Connection refused',
            '- e2 · bia@example.com · 3 tentativa(s) · line one line two',
            '',
            'Para reenviar, use o reprocessamento manual de docs/database.md, seção "Reprocessar um evento em failed".',
        ]));
});

it('sends and marks nothing when no event awaits notice', function () {
    Mail::fake();
    config(['outbox.batch_size' => 100]);
    $events = Mockery::mock(OutboxRepository::class);
    $events->shouldReceive('unnotifiedFailures')->once()->with(100)->andReturn([]);
    $events->shouldNotReceive('markFailureNotified');

    expect((new NotifyFailedOutboxEvents($events))->execute())->toBe(0);
    Mail::assertNothingSent();
});

it('sends one digest and marks the listed events', function () {
    Mail::fake();
    config(['outbox.batch_size' => 2, 'outbox.alert_email' => 'ops@cadastro-feliz.local']);
    $rows = [failedEvent('e1', 'ana@example.com'), failedEvent('e2', 'bia@example.com')];
    $events = Mockery::mock(OutboxRepository::class);
    $events->shouldReceive('unnotifiedFailures')->once()->with(2)->andReturn($rows);
    $events->shouldReceive('markFailureNotified')->once()->with(['e1', 'e2']);

    expect((new NotifyFailedOutboxEvents($events))->execute())->toBe(2);
    Mail::assertSentCount(1);
    Mail::assertSent(FailedEventsDigestMail::class, fn (FailedEventsDigestMail $mail) => $mail->hasTo('ops@cadastro-feliz.local') && $mail->events === $rows);
});

it('marks nothing when the digest fails', function () {
    $events = Mockery::mock(OutboxRepository::class);
    $events->shouldReceive('unnotifiedFailures')->once()->andReturn([failedEvent('e1', 'ana@example.com')]);
    $events->shouldNotReceive('markFailureNotified');
    $pending = Mockery::mock();
    $pending->shouldReceive('send')->once()->andThrow(new RuntimeException('smtp down'));
    Mail::shouldReceive('to')->once()->andReturn($pending);

    expect(fn () => (new NotifyFailedOutboxEvents($events))->execute())->toThrow(RuntimeException::class, 'smtp down');
});

it('exits 1 and logs when the notification fails', function () {
    $this->mock(NotifyFailedOutboxEvents::class)->shouldReceive('execute')->once()
        ->andThrow(new RuntimeException('notify boom'));
    Log::shouldReceive('error')->once()
        ->with('outbox failed-events notification failed', Mockery::on(fn (array $context) => str_contains($context['error'], 'notify boom')));

    $this->artisan('outbox:notify-failed')->assertExitCode(1);
});

it('prints the notified count', function () {
    $this->mock(NotifyFailedOutboxEvents::class)->shouldReceive('execute')->once()->andReturn(2);

    $this->artisan('outbox:notify-failed')->expectsOutput('2 failed event(s) notified.')->assertExitCode(0);
});

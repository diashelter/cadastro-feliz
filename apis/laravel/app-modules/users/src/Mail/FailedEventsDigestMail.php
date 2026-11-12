<?php

namespace Modules\Users\Mail;

use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

/** O resumo ao operador dos eventos que esgotaram as tentativas, em texto simples. */
class FailedEventsDigestMail extends Mailable
{
    /** @param  list<object{id: string, email: string, attempts: int, last_error: ?string}>  $events */
    public function __construct(public array $events) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Cadastro Feliz: '.count($this->events).' evento(s) sem envio');
    }

    public function content(): Content
    {
        return new Content(text: 'users::failed-events-digest-text', with: ['lines' => $this->lines()]);
    }

    /** @return list<string> uma linha por evento; um erro em várias linhas vira uma só. */
    public function lines(): array
    {
        return array_map(fn (object $event) => sprintf(
            '- %s · %s · %d tentativa(s) · %s',
            $event->id,
            $event->email,
            $event->attempts,
            trim((string) preg_replace('/\s+/', ' ', (string) $event->last_error)),
        ), $this->events);
    }
}

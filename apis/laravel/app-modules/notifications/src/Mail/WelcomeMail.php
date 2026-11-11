<?php

namespace Modules\Notifications\Mail;

use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Mail\Mailables\Headers;

class WelcomeMail extends Mailable
{
    public function __construct(public string $name, public string $eventId) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Boas-vindas ao Cadastro Feliz!');
    }

    public function content(): Content
    {
        return new Content(html: 'notifications::welcome', text: 'notifications::welcome-text');
    }

    /** O mesmo evento sai sempre com o mesmo Message-ID, nas três stacks (decisão 22). */
    public function headers(): Headers
    {
        return new Headers(messageId: "{$this->eventId}@cadastro-feliz.local");
    }
}

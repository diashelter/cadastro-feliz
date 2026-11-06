<?php

namespace Modules\Users\Mail;

use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;

class WelcomeMail extends Mailable
{
    public function __construct(public string $name) {}

    public function envelope(): Envelope
    {
        return new Envelope(subject: 'Boas-vindas ao Cadastro Feliz!');
    }

    public function content(): Content
    {
        return new Content(html: 'users::welcome', text: 'users::welcome-text');
    }
}

<?php

// Regras do cadastro. Nomes e padrões: docs/infrastructure.md › Regras de negócio. O envio
// usa as variáveis do outbox porque a regra é a mesma, e a rodada dele vai reutilizá-las.
return [
    'max_attempts' => (int) env('REGISTRATION_MAX_ATTEMPTS', 5),
    'attempt_window' => (int) env('REGISTRATION_ATTEMPT_WINDOW_SECONDS', 900),
    'max_per_ip' => (int) env('REGISTRATION_MAX_PER_IP', 20),
    'ip_window' => (int) env('REGISTRATION_IP_WINDOW_SECONDS', 3600),
    'mail_max_attempts' => (int) env('OUTBOX_MAX_ATTEMPTS', 5),
    'mail_backoff_base' => (int) env('OUTBOX_BACKOFF_BASE_SECONDS', 30),
];

<?php

// Regras do outbox. Nomes e padrões: docs/infrastructure.md › Regras de negócio.
// republish_after precisa ser maior que o tempo máximo de um job (5 s do SMTP, 60 s do
// timeout do Horizon, 90 s do retry_after da fila), para não republicar um envio em andamento.
return [
    'batch_size' => (int) env('OUTBOX_BATCH_SIZE', 100),
    'republish_after' => (int) env('OUTBOX_REPUBLISH_AFTER_SECONDS', 300),
    'max_attempts' => (int) env('OUTBOX_MAX_ATTEMPTS', 5),
    'backoff_base' => (int) env('OUTBOX_BACKOFF_BASE_SECONDS', 30),
    'retention_days' => (int) env('OUTBOX_RETENTION_DAYS', 7),
    'alert_email' => env('OUTBOX_ALERT_EMAIL', 'ops@cadastro-feliz.local'),
];

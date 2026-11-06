<?php

// Regras do cadastro. Nomes e padrões: docs/infrastructure.md › Regras de negócio.
return [
    'max_attempts' => (int) env('REGISTRATION_MAX_ATTEMPTS', 5),
    'attempt_window' => (int) env('REGISTRATION_ATTEMPT_WINDOW_SECONDS', 900),
    'max_per_ip' => (int) env('REGISTRATION_MAX_PER_IP', 20),
    'ip_window' => (int) env('REGISTRATION_IP_WINDOW_SECONDS', 3600),
];

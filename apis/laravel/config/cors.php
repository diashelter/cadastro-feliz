<?php

// O navegador chama a API direto (decisão 12). A origem vai em padrão, não em
// `allowed_origins`: com uma só origem ali, a biblioteca responde com ela a qualquer pedido.
return [
    'paths' => ['users'],
    'allowed_methods' => ['POST', 'OPTIONS'],
    'allowed_origins' => [],
    'allowed_origins_patterns' => ['#^'.preg_quote((string) env('CORS_ALLOWED_ORIGIN', 'http://localhost:3000'), '#').'$#'],
    'allowed_headers' => ['Content-Type'],
    'exposed_headers' => ['Retry-After'],
    'max_age' => 0,
    'supports_credentials' => false,
];

<?php

// Só o que difere do padrão do Horizon: um processo consumindo a fila do e-mail. Tentativas
// e esperas vêm do job, e o painel só abre com APP_ENV=local.
return [
    'defaults' => [
        'supervisor-registration' => [
            'connection' => 'redis',
            'queue' => ['registration-emails'],
            'balance' => 'simple',
            'maxProcesses' => 1,
            'memory' => 128,
            'tries' => 0,
            'timeout' => 60,
            'nice' => 0,
        ],
    ],

    'environments' => [
        'local' => [
            'supervisor-registration' => [],
        ],
    ],
];

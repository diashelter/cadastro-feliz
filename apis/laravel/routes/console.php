<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

// O agendador descarta a saída das tarefas, e com ela o stderr do comando: sem isto, a
// falha do relay não chegaria a `docker logs`. O comando imprime no PID 1 do container.
Schedule::command('outbox:relay')->everySecond()->withoutOverlapping()->appendOutputTo('/proc/1/fd/2');
Schedule::command('outbox:purge')->dailyAt('03:00')->withoutOverlapping()->appendOutputTo('/proc/1/fd/2');
Schedule::command('outbox:notify-failed')->everyFiveMinutes()->withoutOverlapping()->appendOutputTo('/proc/1/fd/2');

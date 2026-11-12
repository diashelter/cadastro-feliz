<?php

/** Os arquivos PHP de app-modules/<glob>, relativos a app-modules. */
function modulePhpFiles(string $glob): array
{
    $root = base_path('app-modules');
    $files = [];
    foreach (glob("{$root}/{$glob}", GLOB_ONLYDIR) as $dir) {
        foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS)) as $file) {
            if ($file->getExtension() === 'php') {
                $files[substr($file->getPathname(), strlen($root) + 1)] = file_get_contents($file->getPathname());
            }
        }
    }

    return $files;
}

it('keeps status and event literals inside the enums', function () {
    $enums = ['users/src/Enums/OutboxStatus.php', 'users/src/Enums/OutboxEventType.php'];
    $found = [];
    foreach (modulePhpFiles('*/src') as $path => $code) {
        if (in_array($path, $enums, true)) {
            continue;
        }
        foreach (['pending', 'published', 'processed', 'failed', 'user.registered'] as $literal) {
            if (preg_match('/[\'"]'.preg_quote($literal, '/').'[\'"]/', $code)) {
                $found[] = "{$path}: {$literal}";
            }
        }
    }

    expect(modulePhpFiles('*/src'))->toHaveKeys($enums)
        ->and($found)->toBe([]);
});

it('opens no transaction in repositories', function () {
    $repositories = modulePhpFiles('*/src/Repositories');
    $found = array_keys(array_filter($repositories, fn (string $code) => preg_match('/transaction\(|beginTransaction/', $code)));

    expect($repositories)->toHaveKeys(['users/src/Repositories/OutboxRepository.php', 'users/src/Repositories/UserRepository.php'])
        ->and($found)->toBe([]);
});

it('has no actions', function () {
    expect(glob(base_path('app-modules/*/src/Actions')))->toBe([])
        ->and(array_keys(array_filter(modulePhpFiles('*'), fn (string $code) => str_contains($code, 'RegisterUserAction'))))->toBe([])
        ->and(class_exists(Modules\Users\UseCases\RegisterUser::class))->toBeTrue();
});

it('has a single users module', function () {
    $require = json_decode(file_get_contents(base_path('composer.json')), true)['require'];
    $packages = array_column(json_decode(file_get_contents(base_path('composer.lock')), true)['packages'], 'dist', 'name');

    expect(is_dir(base_path('app-modules/notifications')))->toBeFalse()
        ->and(is_dir(base_path('app-modules/outbox')))->toBeFalse()
        ->and($require)->not->toHaveKey('modules/notifications')
        ->and($packages)->not->toHaveKey('modules/notifications')
        ->and($packages)->not->toHaveKey('modules/outbox')
        ->and($packages['modules/users']['url'] ?? null)->toBe('app-modules/users')
        ->and($packages['modules/health']['url'] ?? null)->toBe('app-modules/health');
});

it('references no notifications module', function () {
    // Montados por partes, para este arquivo não conter o que procura.
    $terms = ['Modules\\'.'Notifications', 'notifications'.'::'];
    $files = modulePhpFiles('*');
    foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator(base_path('tests'), FilesystemIterator::SKIP_DOTS)) as $file) {
        if ($file->getExtension() === 'php') {
            $files['tests/'.substr($file->getPathname(), strlen(base_path('tests')) + 1)] = file_get_contents($file->getPathname());
        }
    }
    $found = [];
    foreach ($files as $path => $code) {
        foreach ($terms as $term) {
            if (str_contains($code, $term)) {
                $found[] = "{$path}: {$term}";
            }
        }
    }

    expect($files)->toHaveKeys(['users/src/Mail/WelcomeMail.php', 'tests/Feature/ModulesStructureTest.php'])
        ->and($found)->toBe([]);
});

it('keeps the welcome email in users', function () {
    $gone = [
        'Modules\\Users\\Services\\OutboxConsumers',
        'Modules\\Users\\Exceptions\\UnknownOutboxConsumer',
        'Modules\\'.'Notifications\\Providers\\NotificationsServiceProvider',
    ];
    $files = array_map('basename', array_keys(modulePhpFiles('*')));

    expect(class_exists(Modules\Users\Jobs\SendWelcomeEmailJob::class))->toBeTrue()
        ->and(class_exists(Modules\Users\Mail\WelcomeMail::class))->toBeTrue()
        ->and(class_exists(Modules\Users\UseCases\SendWelcomeEmail::class))->toBeTrue()
        ->and(array_filter($gone, 'class_exists'))->toBe([])
        ->and(array_intersect(['OutboxConsumers.php', 'UnknownOutboxConsumer.php', 'NotificationsServiceProvider.php'], $files))->toBe([]);
});

it('injects no database connection', function () {
    $files = modulePhpFiles('*/src');
    foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator(app_path(), FilesystemIterator::SKIP_DOTS)) as $file) {
        $files['app/'.substr($file->getPathname(), strlen(app_path()) + 1)] = file_get_contents($file->getPathname());
    }
    $found = array_keys(array_filter($files, fn (string $code) => str_contains($code, 'ConnectionInterface')));

    $database = [
        Illuminate\Database\ConnectionInterface::class,
        Illuminate\Database\ConnectionResolverInterface::class,
        Illuminate\Database\DatabaseManager::class,
    ];
    $injected = [];
    foreach ([Modules\Users\UseCases\RegisterUser::class, Modules\Users\UseCases\RelayOutboxEvents::class] as $class) {
        foreach ((new ReflectionClass($class))->getConstructor()?->getParameters() ?? [] as $param) {
            $type = (string) $param->getType();
            foreach ($database as $db) {
                if (is_a($type, $db, true)) {
                    $injected[] = "{$class}: \${$param->getName()}";
                }
            }
        }
    }

    expect($files)->toHaveKey('users/src/UseCases/RegisterUser.php')
        ->and($found)->toBe([])
        ->and($injected)->toBe([]);
});

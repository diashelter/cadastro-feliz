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

it('has no outbox module', function () {
    expect(is_dir(base_path('app-modules/outbox')))->toBeFalse()
        ->and(is_file(base_path('app-modules/notifications/composer.json')))->toBeTrue()
        ->and(json_decode(file_get_contents(base_path('app-modules/notifications/composer.json')), true)['autoload']['psr-4'])
        ->toBe(['Modules\\Notifications\\' => 'src/']);
});

it('keeps notifications away from users_outbox and transactions', function () {
    $files = modulePhpFiles('notifications/src');
    $found = [];
    foreach ($files as $path => $code) {
        foreach (['users_outbox', 'DB::', 'ConnectionInterface', 'transaction('] as $term) {
            if (str_contains($code, $term)) {
                $found[] = "{$path}: {$term}";
            }
        }
    }

    expect($files)->toHaveKey('notifications/src/UseCases/SendWelcomeEmail.php')
        ->and($found)->toBe([]);
});

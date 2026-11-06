<?php

use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Bus;
use Modules\Users\Exceptions\EmailAlreadyTaken;
use Modules\Users\Exceptions\RegistrationLimited;
use Modules\Users\Models\User;
use Modules\Users\Repositories\UserRepository;
use Modules\Users\Services\RegistrationLimiter;

function fakeUser(): User
{
    return (new User)->newFromBuilder((object) [
        'id' => '0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e',
        'name' => 'Ana Souza',
        'email' => 'ana@example.com',
        'created_at' => '2026-11-04 09:00:00-03',
        'updated_at' => '2026-11-04 09:00:00-03',
    ]);
}

function fakeLimiter(): Mockery\MockInterface
{
    return test()->mock(RegistrationLimiter::class, function ($mock) {
        $mock->shouldReceive('countAttempt')->byDefault();
        $mock->shouldReceive('reserveQuota')->byDefault();
    });
}

function fakeUsers(): Mockery\MockInterface
{
    return test()->mock(UserRepository::class);
}

it('answers 201 and publishes no job', function () {
    Bus::fake();
    fakeLimiter();
    fakeUsers()->shouldReceive('create')->once()->with('Ana Souza', 'ana@example.com')->andReturn(fakeUser());

    $response = $this->postJson('/users', ['name' => '  Ana Souza ', 'email' => ' ANA@Example.com ', 'role' => 'admin']);

    $response->assertStatus(201);
    expect($response->json())->toBe([
        'data' => [
            'id' => '0190f3a2-7c1e-7b3a-9d5e-2f4a6b8c0d1e',
            'name' => 'Ana Souza',
            'email' => 'ana@example.com',
            'created_at' => '2026-11-04T12:00:00Z',
        ],
        'message' => 'User registered successfully.',
    ]);
    Bus::assertNothingDispatched();
});

it('answers 422 for each field rule', function () {
    Bus::fake();
    $limiter = fakeLimiter();
    $limiter->shouldNotReceive('countAttempt');
    fakeUsers()->shouldNotReceive('create');

    $name = 'Ana';
    $email = 'ana@example.com';
    $cases = [
        [['email' => $email], 'name', 'required', 'The name field is required.'],
        [['name' => '', 'email' => $email], 'name', 'required', 'The name field is required.'],
        [['name' => '   ', 'email' => $email], 'name', 'required', 'The name field is required.'],
        [['name' => 123, 'email' => $email], 'name', 'required', 'The name field is required.'],
        [['name' => str_repeat('a', 256), 'email' => $email], 'name', 'too_long', 'The name must not exceed 255 characters.'],
        [['name' => $name], 'email', 'required', 'The email field is required.'],
        [['name' => $name, 'email' => ''], 'email', 'required', 'The email field is required.'],
        [['name' => $name, 'email' => 123], 'email', 'required', 'The email field is required.'],
        [['name' => $name, 'email' => 'não-é-email'], 'email', 'invalid_format', 'The email must be a valid email address.'],
        [['name' => $name, 'email' => 'ana@'], 'email', 'invalid_format', 'The email must be a valid email address.'],
        [['name' => $name, 'email' => str_repeat('a', 243).'@example.com'], 'email', 'too_long', 'The email must not exceed 254 characters.'],
    ];

    foreach ($cases as [$body, $field, $code, $message]) {
        $response = $this->postJson('/users', $body);

        $response->assertStatus(422);
        expect($response->json())->toBe([
            'message' => 'The given data was invalid.',
            'errors' => [['field' => $field, 'code' => $code, 'message' => $message]],
        ]);
    }
});

it('answers 409 when the email is taken and releases the quota', function () {
    Bus::fake();
    fakeLimiter()->shouldReceive('releaseQuota')->once();
    fakeUsers()->shouldReceive('create')->once()->andThrow(new EmailAlreadyTaken);

    $response = $this->postJson('/users', ['name' => 'Ana', 'email' => 'ana@example.com']);

    $response->assertStatus(409);
    expect($response->json())->toBe([
        'message' => 'The email has already been taken.',
        'errors' => [['field' => 'email', 'code' => 'already_taken', 'message' => 'The email has already been taken.']],
    ]);
    Bus::assertNothingDispatched();
});

it('answers 429 with retry after when the attempts are exceeded', function () {
    Bus::fake();
    fakeLimiter()->shouldReceive('countAttempt')->once()->andThrow(new RegistrationLimited(742));
    fakeUsers()->shouldNotReceive('create');

    $response = $this->postJson('/users', ['name' => 'Ana', 'email' => 'ana@example.com']);

    $response->assertStatus(429);
    $response->assertHeader('Retry-After', '742');
    expect($response->json())->toBe(['message' => 'Too many registration attempts. Try again later.', 'errors' => []]);
});

it('answers 500 without internal detail when the database fails', function () {
    Bus::fake();
    config(['app.debug' => true]);
    fakeLimiter()->shouldReceive('releaseQuota')->once();
    fakeUsers()->shouldReceive('create')->once()->andThrow(new QueryException('pgsql', 'insert', [], new RuntimeException('secret detail')));

    $response = $this->postJson('/users', ['name' => 'Ana', 'email' => 'ana@example.com']);

    $response->assertStatus(500);
    expect($response->getContent())->toBe('{"message":"Internal server error.","errors":[]}');
});

it('denies the horizon panel outside local', function () {
    app()->detectEnvironment(fn () => 'production');

    $this->get('/horizon')->assertStatus(403);
});

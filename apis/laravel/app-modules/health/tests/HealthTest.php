<?php

use Modules\Health\Checks\DatabaseCheck;
use Modules\Health\Checks\LimiterCheck;

function fakeHealthCheck(string $class, bool $passes): void
{
    test()->mock($class, function ($mock) use ($class, $passes) {
        $mock->shouldReceive('name')->andReturn($class === DatabaseCheck::class ? 'database' : 'limiter');
        $expectation = $mock->shouldReceive('run')->once();
        $passes ? $expectation->andReturnNull() : $expectation->andThrow(new RuntimeException('down'));
    });
}

function expectHealthResponse(int $status, string $body): void
{
    $response = test()->get('/health');

    $response->assertStatus($status);
    expect($response->getContent())->toBe($body);
    $response->assertHeader('Content-Type', 'application/json');
    expect($response->headers->get('Cache-Control'))->toContain('no-store');
}

it('returns ok when both checks pass', function () {
    fakeHealthCheck(DatabaseCheck::class, true);
    fakeHealthCheck(LimiterCheck::class, true);

    expectHealthResponse(200, '{"status":"ok","checks":{"database":"ok","limiter":"ok"}}');
});

it('returns 503 when database fails', function () {
    fakeHealthCheck(DatabaseCheck::class, false);
    fakeHealthCheck(LimiterCheck::class, true);

    expectHealthResponse(503, '{"status":"fail","checks":{"database":"fail","limiter":"ok"}}');
});

it('returns 503 when limiter fails', function () {
    fakeHealthCheck(DatabaseCheck::class, true);
    fakeHealthCheck(LimiterCheck::class, false);

    expectHealthResponse(503, '{"status":"fail","checks":{"database":"ok","limiter":"fail"}}');
});

it('returns 503 when both checks fail', function () {
    fakeHealthCheck(DatabaseCheck::class, false);
    fakeHealthCheck(LimiterCheck::class, false);

    expectHealthResponse(503, '{"status":"fail","checks":{"database":"fail","limiter":"fail"}}');
});

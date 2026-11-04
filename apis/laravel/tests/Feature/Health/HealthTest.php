<?php

namespace Tests\Feature\Health;

use App\Modules\Health\Checks\DatabaseCheck;
use App\Modules\Health\Checks\LimiterCheck;
use RuntimeException;
use Tests\TestCase;

class HealthTest extends TestCase
{
    private function passing(string $class): void
    {
        $this->mock($class, function ($mock) use ($class) {
            $mock->shouldReceive('name')->andReturn($class === DatabaseCheck::class ? 'database' : 'limiter');
            $mock->shouldReceive('run')->once()->andReturnNull();
        });
    }

    private function failing(string $class): void
    {
        $this->mock($class, function ($mock) use ($class) {
            $mock->shouldReceive('name')->andReturn($class === DatabaseCheck::class ? 'database' : 'limiter');
            $mock->shouldReceive('run')->once()->andThrow(new RuntimeException('down'));
        });
    }

    private function assertHealthHeaders($response): void
    {
        $response->assertHeader('Content-Type', 'application/json');
        $this->assertStringContainsString('no-store', $response->headers->get('Cache-Control'));
    }

    public function test_returns_ok_when_both_checks_pass(): void
    {
        $this->passing(DatabaseCheck::class);
        $this->passing(LimiterCheck::class);

        $response = $this->get('/health');

        $response->assertStatus(200);
        $this->assertSame('{"status":"ok","checks":{"database":"ok","limiter":"ok"}}', $response->getContent());
        $this->assertHealthHeaders($response);
    }

    public function test_returns_503_when_database_fails(): void
    {
        $this->failing(DatabaseCheck::class);
        $this->passing(LimiterCheck::class);

        $response = $this->get('/health');

        $response->assertStatus(503);
        $this->assertSame('{"status":"fail","checks":{"database":"fail","limiter":"ok"}}', $response->getContent());
        $this->assertHealthHeaders($response);
    }

    public function test_returns_503_when_limiter_fails(): void
    {
        $this->passing(DatabaseCheck::class);
        $this->failing(LimiterCheck::class);

        $response = $this->get('/health');

        $response->assertStatus(503);
        $this->assertSame('{"status":"fail","checks":{"database":"ok","limiter":"fail"}}', $response->getContent());
        $this->assertHealthHeaders($response);
    }

    public function test_returns_503_when_both_checks_fail(): void
    {
        $this->failing(DatabaseCheck::class);
        $this->failing(LimiterCheck::class);

        $response = $this->get('/health');

        $response->assertStatus(503);
        $this->assertSame('{"status":"fail","checks":{"database":"fail","limiter":"fail"}}', $response->getContent());
        $this->assertHealthHeaders($response);
    }
}

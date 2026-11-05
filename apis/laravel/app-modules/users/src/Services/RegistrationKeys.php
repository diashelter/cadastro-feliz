<?php

namespace Modules\Users\Services;

/** As chaves do redis-limiter, iguais nas três stacks (docs/api-contract.md). */
class RegistrationKeys
{
    public static function attempts(string $ip, string $email): string
    {
        return 'registration:attempts:'.hash('sha256', self::canonicalIp($ip).'|'.$email);
    }

    public static function quota(string $ip): string
    {
        return 'registration:ip:'.hash('sha256', self::canonicalIp($ip));
    }

    public static function canonicalIp(string $ip): string
    {
        $ip = explode('%', $ip, 2)[0];
        $binary = @inet_pton($ip);

        if ($binary === false) {
            return $ip;
        }

        $text = (string) inet_ntop($binary);

        return str_starts_with($text, '::ffff:') && str_contains($text, '.') ? substr($text, 7) : $text;
    }
}

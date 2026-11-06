<?php

namespace Modules\Users\Exceptions;

use RuntimeException;

class RegistrationLimited extends RuntimeException
{
    public function __construct(public readonly int $retryAfter)
    {
        parent::__construct('registration limited');
    }
}

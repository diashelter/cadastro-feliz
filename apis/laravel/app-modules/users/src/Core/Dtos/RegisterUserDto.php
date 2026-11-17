<?php

namespace Modules\Users\Core\Dtos;

/** Os dados do cadastro já validados e normalizados por quem chama o caso de uso. */
final readonly class RegisterUserDto
{
    public function __construct(
        public string $name,
        public string $email,
    ) {}
}

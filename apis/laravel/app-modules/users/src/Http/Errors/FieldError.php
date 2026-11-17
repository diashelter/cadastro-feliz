<?php

namespace Modules\Users\Http\Errors;

/**
 * Os itens de `errors` de POST /users. O valor é o par `field` + `code`, que é o contrato
 * estável (docs/api-contract.md); a mensagem canônica serve só para diagnóstico.
 */
enum FieldError: string
{
    case NameRequired = 'name.required';
    case NameTooLong = 'name.too_long';
    case EmailRequired = 'email.required';
    case EmailTooLong = 'email.too_long';
    case EmailInvalidFormat = 'email.invalid_format';
    case EmailAlreadyTaken = 'email.already_taken';

    public function message(): string
    {
        return match ($this) {
            self::NameRequired => 'The name field is required.',
            self::NameTooLong => 'The name must not exceed 255 characters.',
            self::EmailRequired => 'The email field is required.',
            self::EmailTooLong => 'The email must not exceed 254 characters.',
            self::EmailInvalidFormat => 'The email must be a valid email address.',
            self::EmailAlreadyTaken => 'The email has already been taken.',
        };
    }

    /** @return array{field: string, code: string, message: string} */
    public function toItem(): array
    {
        [$field, $code] = explode('.', $this->value, 2);

        return ['field' => $field, 'code' => $code, 'message' => $this->message()];
    }
}

<?php

namespace Modules\Users\Http\Requests;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\HttpResponseException;

/**
 * Regras e forma do 422 do contrato. O formato de validação do framework não serve
 * (decisão 14): cada regra violada vira um item com `field` e `code`.
 */
class StoreUserRequest extends FormRequest
{
    public const array MESSAGES = [
        'name' => [
            'required' => 'The name field is required.',
            'too_long' => 'The name must not exceed 255 characters.',
        ],
        'email' => [
            'required' => 'The email field is required.',
            'too_long' => 'The email must not exceed 254 characters.',
            'invalid_format' => 'The email must be a valid email address.',
            'already_taken' => 'The email has already been taken.',
        ],
    ];

    private const array CODES = [
        'Required' => 'required',
        'String' => 'required',
        'Max' => 'too_long',
        'Email' => 'invalid_format',
    ];

    public function authorize(): bool
    {
        return true;
    }

    /** @return array<string, list<string>> */
    public function rules(): array
    {
        return [
            'name' => ['bail', 'required', 'string', 'max:255'],
            // `max` antes de `email`: um e-mail longo responde too_long, não invalid_format.
            'email' => ['bail', 'required', 'string', 'max:254', 'email'],
        ];
    }

    /** @return array{field: string, code: string, message: string} */
    public static function item(string $field, string $code): array
    {
        return ['field' => $field, 'code' => $code, 'message' => self::MESSAGES[$field][$code]];
    }

    protected function failedValidation(Validator $validator): void
    {
        $errors = [];

        foreach ($validator->failed() as $field => $rules) {
            $errors[] = self::item($field, self::CODES[array_key_first($rules)]);
        }

        throw new HttpResponseException(response()->json([
            'message' => 'The given data was invalid.',
            'errors' => $errors,
        ], 422));
    }
}

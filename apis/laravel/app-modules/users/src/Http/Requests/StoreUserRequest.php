<?php

namespace Modules\Users\Http\Requests;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\HttpResponseException;
use Modules\Users\Core\Dtos\RegisterUserDto;
use Modules\Users\Http\Errors\FieldError;
use Modules\Users\Http\Responses\RegistrationResponses;

/**
 * As regras de POST /users. O formato de validação do framework não serve (decisão 14):
 * cada regra violada vira um FieldError, e o 422 é montado em RegistrationResponses.
 */
class StoreUserRequest extends FormRequest
{
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

    /**
     * Os dados validados, normalizados para o caso de uso. A normalização vem depois da
     * validação, na ordem do contrato; o trim antes dela é do middleware TrimStrings.
     */
    public function toDto(): RegisterUserDto
    {
        return new RegisterUserDto(
            name: trim($this->validated('name')),
            email: mb_strtolower(trim($this->validated('email'))),
        );
    }

    protected function failedValidation(Validator $validator): void
    {
        throw new HttpResponseException(RegistrationResponses::invalid($this->errorsFrom($validator)));
    }

    /**
     * Um item por campo, pela primeira regra violada (as regras usam `bail`).
     *
     * @return list<FieldError>
     */
    private function errorsFrom(Validator $validator): array
    {
        $errors = [];

        foreach ($validator->failed() as $field => $rules) {
            $errors[] = $this->errorFor($field, array_key_first($rules));
        }

        return $errors;
    }

    /**
     * Traduz a regra do Laravel para o código do contrato; tipo errado conta como `required`.
     * Uma regra sem tradução lança UnhandledMatchError em vez de responder um código inventado.
     */
    private function errorFor(string $field, string $rule): FieldError
    {
        $code = match ($rule) {
            'Required', 'String' => 'required',
            'Max' => 'too_long',
            'Email' => 'invalid_format',
        };

        return FieldError::from("{$field}.{$code}");
    }
}

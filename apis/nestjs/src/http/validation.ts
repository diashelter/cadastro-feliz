import { UnprocessableEntityException, ValidationError, ValidationPipe } from '@nestjs/common';
import { ValidatorConstraint, ValidatorConstraintInterface, ValidationArguments } from 'class-validator';

// A forma do 422 do contrato (docs/api-contract.md › 422). O formato de validação do Nest não
// serve (decisão 14): cada campo inválido vira um item com `field`, `code` e `message`, na
// ordem dos campos, e a primeira regra violada de cada campo é a que conta.

export type Field = 'name' | 'email';
export type ErrorCode = 'required' | 'too_long' | 'invalid_format' | 'already_taken';

export const MESSAGES: Record<Field, Partial<Record<ErrorCode, string>>> = {
  name: {
    required: 'The name field is required.',
    too_long: 'The name must not exceed 255 characters.',
  },
  email: {
    required: 'The email field is required.',
    too_long: 'The email must not exceed 254 characters.',
    invalid_format: 'The email must be a valid email address.',
    already_taken: 'The email has already been taken.',
  },
};

const FIELDS: Field[] = ['name', 'email'];

export interface ErrorItem {
  field: Field;
  code: ErrorCode;
  message: string;
}

export function errorItem(field: Field, code: ErrorCode): ErrorItem {
  return { field, code, message: MESSAGES[field][code] ?? '' };
}

/** Como a Laravel recebe o texto: sem espaços nas pontas, e vazio vira ausente. */
export function trimToNull(value: unknown): unknown {
  if (typeof value !== 'string') {
    return value;
  }
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

const length = (value: string): number => [...value].length;

export function nameErrorCode(value: unknown): ErrorCode | null {
  if (typeof value !== 'string') {
    return 'required';
  }
  return length(value) > 255 ? 'too_long' : null;
}

const LOCAL_ATOM = /^[^\s@"(),:;<>[\]\\.]+$/u;
const DOMAIN_LABEL = /^[\p{L}\p{N}](?:[\p{L}\p{N}-]{0,61}[\p{L}\p{N}])?$/u;

/** Só sintaxe, sem DNS. `too_long` vem antes do formato, como no contrato. */
export function emailErrorCode(value: unknown): ErrorCode | null {
  if (typeof value !== 'string') {
    return 'required';
  }
  if (length(value) > 254) {
    return 'too_long';
  }
  const at = value.lastIndexOf('@');
  if (at <= 0 || at === value.length - 1) {
    return 'invalid_format';
  }
  const local = value.slice(0, at);
  const domain = value.slice(at + 1);
  const localOk = local.split('.').every((atom) => LOCAL_ATOM.test(atom));
  const domainOk = domain.split('.').every((label) => DOMAIN_LABEL.test(label));
  return localOk && domainOk ? null : 'invalid_format';
}

@ValidatorConstraint({ name: 'name' })
export class NameRule implements ValidatorConstraintInterface {
  validate(value: unknown): boolean {
    return nameErrorCode(value) === null;
  }

  defaultMessage(args: ValidationArguments): string {
    return nameErrorCode(args.value) ?? '';
  }
}

@ValidatorConstraint({ name: 'email' })
export class EmailRule implements ValidatorConstraintInterface {
  validate(value: unknown): boolean {
    return emailErrorCode(value) === null;
  }

  defaultMessage(args: ValidationArguments): string {
    return emailErrorCode(args.value) ?? '';
  }
}

export function invalidBody(items: ErrorItem[]): { message: string; errors: ErrorItem[] } {
  return { message: 'The given data was invalid.', errors: items };
}

export function contractErrors(errors: ValidationError[]): ErrorItem[] {
  return FIELDS.flatMap((field) => {
    const error = errors.find((e) => e.property === field);
    const code = error?.constraints ? Object.values(error.constraints)[0] : undefined;
    return code ? [errorItem(field, code as ErrorCode)] : [];
  });
}

/** O pipe global da api: só o 422 do contrato, nunca o 400 do Nest. */
export function contractValidationPipe(): ValidationPipe {
  return new ValidationPipe({
    transform: true,
    forbidUnknownValues: false,
    exceptionFactory: (errors) => new UnprocessableEntityException(invalidBody(contractErrors(errors))),
  });
}

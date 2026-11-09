import 'reflect-metadata';
import { UnprocessableEntityException } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import { CreateUserDto } from '../modules/users/dto/create-user.dto';
import { parseObject } from './json-body';
import { contractValidationPipe } from './validation';

const metadata = { type: 'body' as const, metatype: CreateUserDto, data: '' };

async function errorsFor(body: unknown): Promise<unknown> {
  try {
    await contractValidationPipe().transform(body, metadata);
  } catch (error) {
    expect(error).toBeInstanceOf(UnprocessableEntityException);
    return (error as UnprocessableEntityException).getResponse();
  }
  return null;
}

/** Um e-mail com `size` caracteres e rótulos de domínio de até 63, como RG3 monta. */
const longEmail = (size: number): string => {
  const rest = size - 64 - 1 - 4;
  const labels = [61, 61, rest - 61 - 61 - 2].map((n) => 'c'.repeat(n));
  return `${'a'.repeat(64)}@${labels.join('.')}.com`;
};

const required = (field: 'name' | 'email') => ({
  field,
  code: 'required',
  message: `The ${field} field is required.`,
});

describe('validation errors', () => {
  it('malformed json answers the contract 422', async () => {
    const expected = { message: 'The given data was invalid.', errors: [required('name'), required('email')] };
    for (const text of ['{"name": ', '[]', 'null', '"x"', '1']) {
      expect(await errorsFor(parseObject(text))).toEqual(expected);
    }
  });

  it('maps each rule to its code', async () => {
    const mail = 'ana@example.com';
    const cases: [unknown, string, string][] = [
      [{ email: mail }, 'name', 'required'],
      [{ name: '   ', email: mail }, 'name', 'required'],
      [{ name: 123, email: mail }, 'name', 'required'],
      [{ name: 'a'.repeat(256), email: mail }, 'name', 'too_long'],
      [{ name: 'Ana', email: 123 }, 'email', 'required'],
      [{ name: 'Ana', email: 'não-é-email' }, 'email', 'invalid_format'],
      [{ name: 'Ana', email: 'ana@' }, 'email', 'invalid_format'],
      [{ name: 'Ana', email: longEmail(255) }, 'email', 'too_long'],
    ];
    for (const [body, field, code] of cases) {
      const response = (await errorsFor(body)) as { errors: { field: string; code: string }[] };
      expect(response.errors.map((e) => [e.field, e.code])).toEqual([[field, code]]);
    }
  });

  it('accepts the longest valid values', async () => {
    expect(await errorsFor({ name: 'a'.repeat(255), email: longEmail(254) })).toBeNull();
  });
});

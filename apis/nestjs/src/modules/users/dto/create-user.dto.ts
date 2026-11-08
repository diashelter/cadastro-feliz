import { Transform } from 'class-transformer';
import { Validate } from 'class-validator';
import { EmailRule, NameRule, trimToNull } from '../../../http/validation';

/** O corpo de POST /users. Campos extras são ignorados (docs/api-contract.md). */
export class CreateUserDto {
  @Transform(({ value }) => trimToNull(value))
  @Validate(NameRule)
  name: string;

  @Transform(({ value }) => trimToNull(value))
  @Validate(EmailRule)
  email: string;
}

import { TypeOrmModuleOptions } from '@nestjs/typeorm';
import { env } from './config';
import { UserOutboxEvent } from './modules/outbox/user-outbox-event.entity';
import { User } from './modules/users/user.entity';

/**
 * A conexão com o PostgreSQL comum às três stacks. O TypeORM nunca altera o schema: sem
 * sincronização e sem migrations, porque database/migrations é a única fonte (decisão 24).
 */
export function typeOrmOptions(): TypeOrmModuleOptions {
  return {
    type: 'postgres',
    ...env.database(),
    entities: [User, UserOutboxEvent],
    synchronize: false,
    migrationsRun: false,
    migrations: [],
    // Uma conexão desiste em 1 s: o banco fora do ar responde 500 sem segurar a requisição.
    extra: { connectionTimeoutMillis: 1000 },
  };
}

import { Module } from '@nestjs/common';
import { UsersModule } from '../users/users.module';
import { HealthController } from './health.controller';

/** GET /health, com a conexão do redis-limiter que o cadastro usa. */
@Module({
  imports: [UsersModule],
  controllers: [HealthController],
})
export class HealthModule {}

import { Module, OnApplicationShutdown, Inject } from '@nestjs/common';
import Redis from 'ioredis';
import { env } from '../../config';
import { OutboxModule } from '../outbox/outbox.module';
import { LIMITER_REDIS, RegistrationAttemptLimiter } from './registration-attempt-limiter.service';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

/**
 * A conexão com o redis-limiter falha rápido: 1 s para conectar e para cada comando, sem
 * retentar nem enfileirar, para a api responder 500 sem segurar a requisição.
 */
export function limiterConnection(): Redis {
  const redis = new Redis({
    ...env.limiter(),
    connectTimeout: 1000,
    commandTimeout: 1000,
    maxRetriesPerRequest: 0,
    enableOfflineQueue: false,
    retryStrategy: () => 500,
  });
  // Sem ouvinte, um erro de conexão derrubaria o processo; o motivo aparece em cada resposta 500.
  redis.on('error', () => undefined);
  return redis;
}

/** Só da api: o worker não cadastra ninguém. */
@Module({
  imports: [OutboxModule],
  controllers: [UsersController],
  providers: [{ provide: LIMITER_REDIS, useFactory: limiterConnection }, RegistrationAttemptLimiter, UsersService],
  exports: [LIMITER_REDIS],
})
export class UsersModule implements OnApplicationShutdown {
  constructor(@Inject(LIMITER_REDIS) private readonly redis: Redis) {}

  onApplicationShutdown(): void {
    this.redis.disconnect();
  }
}

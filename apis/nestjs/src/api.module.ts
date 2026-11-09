import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { typeOrmOptions } from './database';
import { HealthModule } from './modules/health/health.module';
import { UsersModule } from './modules/users/users.module';

/**
 * O módulo raiz da api (src/main.ts). Não importa o BullModule nem nada de fila: a api não
 * abre conexão com o redis da stack (Key decision 1 de .design/nestjs-stack.md).
 */
@Module({
  imports: [TypeOrmModule.forRoot(typeOrmOptions()), UsersModule, HealthModule],
})
export class ApiModule {}

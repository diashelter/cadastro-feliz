import { Module } from '@nestjs/common';
import { OutboxRepository } from './outbox.repository';

/**
 * O evento e as consultas dele, importados pela api e pelo worker. Não importa nada de fila:
 * a api não abre conexão com o redis da stack (Key decision 1 de .design/nestjs-stack.md).
 */
@Module({
  providers: [OutboxRepository],
  exports: [OutboxRepository],
})
export class OutboxModule {}

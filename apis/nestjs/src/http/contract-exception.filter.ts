import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger, NotFoundException } from '@nestjs/common';
import type { Response } from 'express';

/**
 * Toda resposta de erro na forma do contrato, `message` e `errors` (docs/api-contract.md › Forma
 * do corpo de erro). Uma falha inesperada responde 500 sem detalhe, com o motivo no log.
 */
@Catch()
export class ContractExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger('Http');

  catch(exception: unknown, host: ArgumentsHost): void {
    const res = host.switchToHttp().getResponse<Response>();

    if (exception instanceof NotFoundException) {
      res.status(404).json({ message: 'Not found.', errors: [] });
      return;
    }
    if (exception instanceof HttpException && exception.getStatus() < 500) {
      const body = exception.getResponse();
      res
        .status(exception.getStatus())
        .json(typeof body === 'object' && body !== null && 'errors' in body ? body : { message: exception.message, errors: [] });
      return;
    }

    this.logger.error(`request failed: ${exception instanceof Error ? exception.message : String(exception)}`);
    res.status(500).json({ message: 'Internal server error.', errors: [] });
  }
}

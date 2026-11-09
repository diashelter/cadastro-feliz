import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { ApiModule } from './api.module';
import { env } from './config';
import { ContractExceptionFilter } from './http/contract-exception.filter';
import { corsFor } from './http/cors';
import { readJsonBody } from './http/json-body';
import { contractValidationPipe } from './http/validation';

// A api: POST /users e GET /health na porta 8080 (docs/stacks.md › NestJS).
async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(ApiModule, { bodyParser: false });
  app.use(readJsonBody);
  app.enableCors(corsFor(env.corsAllowedOrigin()));
  app.useGlobalPipes(contractValidationPipe());
  app.useGlobalFilters(new ContractExceptionFilter());
  app.enableShutdownHooks();
  await app.listen(8080, '0.0.0.0');
}

void bootstrap();

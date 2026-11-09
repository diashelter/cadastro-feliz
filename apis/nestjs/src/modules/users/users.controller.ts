import { Body, Controller, HttpCode, Logger, Post, Req, Res } from '@nestjs/common';
import type { Request, Response } from 'express';
import { errorItem, MESSAGES } from '../../http/validation';
import { CreateUserDto } from './dto/create-user.dto';
import { RegistrationLimited } from './registration-attempt-limiter.service';
import { EmailAlreadyTaken, UsersService } from './users.service';

/**
 * POST /users (docs/api-contract.md). Toda indisponibilidade responde 500: o motivo vai para
 * o log, e a resposta não traz detalhe interno.
 */
@Controller('users')
export class UsersController {
  private readonly logger = new Logger(UsersController.name);

  constructor(private readonly users: UsersService) {}

  @Post()
  @HttpCode(201)
  async store(@Body() body: CreateUserDto, @Req() req: Request, @Res({ passthrough: true }) res: Response) {
    // O IP é o da conexão TCP: a api é publicada direto, sem proxy de confiança, e
    // X-Forwarded-For é ignorado (docs/api-contract.md › IP do cliente).
    const ip = req.socket.remoteAddress ?? '';
    try {
      const user = await this.users.register(body.name, body.email, ip);
      return { data: user, message: 'User registered successfully.' };
    } catch (error) {
      if (error instanceof EmailAlreadyTaken) {
        res.status(409);
        return { message: MESSAGES.email.already_taken, errors: [errorItem('email', 'already_taken')] };
      }
      if (error instanceof RegistrationLimited) {
        res.status(429).setHeader('Retry-After', String(error.retryAfter));
        return { message: 'Too many registration attempts. Try again later.', errors: [] };
      }
      this.logger.error(`registration failed: ${(error as Error).message}`);
      res.status(500);
      return { message: 'Internal server error.', errors: [] };
    }
  }
}

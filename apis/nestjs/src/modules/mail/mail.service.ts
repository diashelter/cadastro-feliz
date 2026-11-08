import { Injectable, OnApplicationShutdown } from '@nestjs/common';
import nodemailer, { Transporter } from 'nodemailer';
import { env } from '../../config';
import { messageIdFor, SENDER_NAME, WELCOME_SUBJECT, welcomeHtml, welcomeText } from './welcome-mail';

/**
 * O envio pelo SMTP. Conectar, esperar a saudação e cada leitura desistem em 5 s, abaixo do
 * lock de 30 s do job e dos 300 s de republicação (Key decision 4 de .design/nestjs-stack.md).
 */
@Injectable()
export class MailService implements OnApplicationShutdown {
  private readonly smtp = env.smtp();
  private readonly transport: Transporter = nodemailer.createTransport({
    host: this.smtp.host,
    port: this.smtp.port,
    secure: false,
    connectionTimeout: 5000,
    greetingTimeout: 5000,
    socketTimeout: 5000,
  });

  async sendWelcome(to: string, name: string, eventId: string): Promise<void> {
    await this.transport.sendMail({
      from: { name: SENDER_NAME, address: this.smtp.from },
      to,
      subject: WELCOME_SUBJECT,
      text: welcomeText(name),
      html: welcomeHtml(name),
      messageId: messageIdFor(eventId),
    });
  }

  onApplicationShutdown(): void {
    this.transport.close();
  }
}

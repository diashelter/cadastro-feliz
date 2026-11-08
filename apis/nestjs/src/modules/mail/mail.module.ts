import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { EMAIL_QUEUE } from '../../queues';
import { OutboxModule } from '../outbox/outbox.module';
import { MailService } from './mail.service';
import { RegistrationEmailProcessor } from './registration-email.processor';

/** O consumidor de registration-emails. Só do worker. */
@Module({
  imports: [BullModule.registerQueue({ name: EMAIL_QUEUE }), OutboxModule],
  providers: [MailService, RegistrationEmailProcessor],
})
export class MailModule {}

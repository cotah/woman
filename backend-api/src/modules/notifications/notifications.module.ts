import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bullmq';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { SmsProvider } from './providers/sms.provider';
import { PushProvider } from './providers/push.provider';
import { VoiceProvider } from './providers/voice.provider';
import { AlertDelivery } from './entities/alert-delivery.entity';
import { ContactResponse } from './entities/contact-response.entity';
import { ContactsModule } from '../contacts/contacts.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([AlertDelivery, ContactResponse]),
    BullModule.registerQueue({ name: 'alert-dispatch' }),
    forwardRef(() => ContactsModule),
  ],
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    SmsProvider,
    PushProvider,
    VoiceProvider,
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}

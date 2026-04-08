import { Module, forwardRef } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ContactsController } from './contacts.controller';
import { ContactPortalController } from './contact-portal.controller';
import { ContactsService } from './contacts.service';
import { ContactAccessService } from './contact-access.service';
import { TrustedContact } from './entities/trusted-contact.entity';
import { ContactAccessToken } from './entities/contact-access-token.entity';
import { Incident } from '../incidents/entities/incident.entity';
import { IncidentEvent } from '../incidents/entities/incident-event.entity';
import { IncidentLocation } from '../incidents/entities/incident-location.entity';
import { User } from '../users/entities/user.entity';
import { NotificationsModule } from '../notifications/notifications.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      TrustedContact,
      ContactAccessToken,
      Incident,
      IncidentEvent,
      IncidentLocation,
      User,
    ]),
    forwardRef(() => NotificationsModule),
  ],
  controllers: [ContactsController, ContactPortalController],
  providers: [ContactsService, ContactAccessService],
  exports: [ContactsService, ContactAccessService],
})
export class ContactsModule {}

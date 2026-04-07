import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ContactsController } from './contacts.controller';
import { ContactsService } from './contacts.service';
import { ContactAccessService } from './contact-access.service';
import { TrustedContact } from './entities/trusted-contact.entity';
import { ContactAccessToken } from './entities/contact-access-token.entity';

@Module({
  imports: [TypeOrmModule.forFeature([TrustedContact, ContactAccessToken])],
  controllers: [ContactsController],
  providers: [ContactsService, ContactAccessService],
  exports: [ContactsService, ContactAccessService],
})
export class ContactsModule {}

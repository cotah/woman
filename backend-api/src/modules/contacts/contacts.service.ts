import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { randomBytes } from 'crypto';
import { TrustedContact } from './entities/trusted-contact.entity';
import { CreateContactDto } from './dto/create-contact.dto';
import { UpdateContactDto } from './dto/update-contact.dto';

@Injectable()
export class ContactsService {
  private readonly logger = new Logger(ContactsService.name);

  constructor(
    @InjectRepository(TrustedContact)
    private readonly contactsRepository: Repository<TrustedContact>,
  ) {}

  async findAllByUser(userId: string): Promise<TrustedContact[]> {
    return this.contactsRepository.find({
      where: { userId },
      order: { priority: 'ASC', createdAt: 'ASC' },
    });
  }

  async findOneByUser(id: string, userId: string): Promise<TrustedContact> {
    const contact = await this.contactsRepository.findOne({
      where: { id, userId },
    });

    if (!contact) {
      throw new NotFoundException(`Contact with id "${id}" not found`);
    }

    return contact;
  }

  async create(userId: string, dto: CreateContactDto): Promise<TrustedContact> {
    const verificationToken = randomBytes(32).toString('hex');

    const contact = this.contactsRepository.create({
      ...dto,
      userId,
      verificationToken,
    });

    const saved = await this.contactsRepository.save(contact);
    this.logger.log(`Contact created: ${saved.id} for user ${userId}`);

    return saved;
  }

  async update(
    id: string,
    userId: string,
    dto: UpdateContactDto,
  ): Promise<TrustedContact> {
    const contact = await this.findOneByUser(id, userId);

    Object.assign(contact, dto);
    const updated = await this.contactsRepository.save(contact);

    this.logger.log(`Contact updated: ${id} by user ${userId}`);
    return updated;
  }

  async remove(id: string, userId: string): Promise<void> {
    const contact = await this.findOneByUser(id, userId);

    await this.contactsRepository.softRemove(contact);
    this.logger.log(`Contact soft-deleted: ${id} by user ${userId}`);
  }
}

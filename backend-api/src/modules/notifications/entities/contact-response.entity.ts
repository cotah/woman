import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  Index,
} from 'typeorm';

export type ContactResponseType =
  | 'trying_to_reach'
  | 'could_not_reach'
  | 'going_to_location'
  | 'calling_authorities'
  | 'marked_reviewed';

@Entity('contact_responses')
@Index('idx_contact_responses_incident', ['incidentId'])
export class ContactResponse {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'incident_id', type: 'uuid' })
  incidentId: string;

  @Column({ name: 'contact_id', type: 'uuid' })
  contactId: string;

  @Column({
    name: 'response_type',
    type: 'enum',
    enum: [
      'trying_to_reach',
      'could_not_reach',
      'going_to_location',
      'calling_authorities',
      'marked_reviewed',
    ],
  })
  responseType: ContactResponseType;

  @Column({ type: 'text', nullable: true })
  note: string | null;

  @Column({ name: 'responded_at', type: 'timestamptz', default: () => 'NOW()' })
  respondedAt: Date;
}

import { DataSource } from 'typeorm';
import * as bcrypt from 'bcrypt';
import * as dotenv from 'dotenv';

dotenv.config();

const BCRYPT_ROUNDS = 10;

async function runSeed() {
  const dataSource = new DataSource({
    type: 'postgres',
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    username: process.env.DB_USERNAME || 'safecircle',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_DATABASE || 'safecircle',
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
    logging: true,
  });

  await dataSource.initialize();
  console.log('Database connection established.');

  const queryRunner = dataSource.createQueryRunner();
  await queryRunner.startTransaction();

  try {
    // ── 1. Admin user ──────────────────────────────────────────
    const adminPasswordHash = await bcrypt.hash('Admin123!', BCRYPT_ROUNDS);

    const [adminUser] = await queryRunner.query(
      `INSERT INTO users (email, password_hash, first_name, last_name, phone, role, is_active, email_verified, onboarding_completed)
       VALUES ($1, $2, $3, $4, $5, $6, true, true, true)
       ON CONFLICT (email) DO UPDATE SET
         password_hash = EXCLUDED.password_hash,
         role = EXCLUDED.role,
         updated_at = NOW()
       RETURNING id`,
      [
        'admin@safecircle.app',
        adminPasswordHash,
        'Admin',
        'SafeCircle',
        '+15550000001',
        'admin',
      ],
    );
    console.log(`Admin user seeded: ${adminUser.id}`);

    // ── 2. Regular test user ───────────────────────────────────
    const userPasswordHash = await bcrypt.hash('User123!', BCRYPT_ROUNDS);

    const [testUser] = await queryRunner.query(
      `INSERT INTO users (email, password_hash, first_name, last_name, phone, role, is_active, email_verified, onboarding_completed)
       VALUES ($1, $2, $3, $4, $5, $6, true, true, true)
       ON CONFLICT (email) DO UPDATE SET
         password_hash = EXCLUDED.password_hash,
         updated_at = NOW()
       RETURNING id`,
      [
        'user@safecircle.app',
        userPasswordHash,
        'Test',
        'User',
        '+15550000002',
        'user',
      ],
    );
    console.log(`Test user seeded: ${testUser.id}`);

    // ── 3. Trusted contacts for test user ──────────────────────
    const contacts = [
      {
        name: 'Alice Johnson',
        relationship: 'Sister',
        phone: '+15550000010',
        email: 'alice@example.com',
        priority: 1,
        canReceiveSms: true,
        canReceiveVoiceCall: true,
        canAccessLocation: true,
      },
      {
        name: 'Bob Martinez',
        relationship: 'Partner',
        phone: '+15550000011',
        email: 'bob@example.com',
        priority: 2,
        canReceiveSms: true,
        canReceiveVoiceCall: false,
        canAccessLocation: true,
      },
      {
        name: 'Carol Nguyen',
        relationship: 'Friend',
        phone: '+15550000012',
        email: 'carol@example.com',
        priority: 3,
        canReceiveSms: true,
        canReceiveVoiceCall: false,
        canAccessLocation: false,
      },
    ];

    // Remove existing contacts for idempotency
    await queryRunner.query(
      `DELETE FROM trusted_contacts WHERE user_id = $1`,
      [testUser.id],
    );

    for (const contact of contacts) {
      await queryRunner.query(
        `INSERT INTO trusted_contacts
           (user_id, name, relationship, phone, email, priority,
            can_receive_sms, can_receive_voice_call, can_access_location, is_verified, verified_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, true, NOW())`,
        [
          testUser.id,
          contact.name,
          contact.relationship,
          contact.phone,
          contact.email,
          contact.priority,
          contact.canReceiveSms,
          contact.canReceiveVoiceCall,
          contact.canAccessLocation,
        ],
      );
      console.log(`Contact seeded: ${contact.name} (priority ${contact.priority})`);
    }

    // ── 4. Default emergency settings for test user ────────────
    await queryRunner.query(
      `INSERT INTO emergency_settings
         (user_id, countdown_duration_seconds, normal_cancel_method, audio_consent,
          auto_record_audio, allow_ai_analysis, enable_test_mode, emergency_message)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (user_id) DO UPDATE SET
         countdown_duration_seconds = EXCLUDED.countdown_duration_seconds,
         enable_test_mode = EXCLUDED.enable_test_mode,
         updated_at = NOW()`,
      [
        testUser.id,
        5,
        'tap_pattern',
        'record_and_analyze',
        true,
        true,
        true,
        'I need help. This is an emergency alert from SafeCircle.',
      ],
    );
    console.log('Emergency settings seeded for test user.');

    // ── 5. Feature flags (from migration SQL, upsert) ──────────
    const featureFlags = [
      { key: 'audio_recording', name: 'Audio Recording', description: 'Enable audio recording during incidents', enabled: true, phase: 1 },
      { key: 'audio_ai_analysis', name: 'Audio AI Analysis', description: 'Enable AI-powered audio analysis', enabled: true, phase: 1 },
      { key: 'sms_alerts', name: 'SMS Alerts', description: 'Enable SMS alert delivery', enabled: true, phase: 1 },
      { key: 'push_alerts', name: 'Push Notifications', description: 'Enable push notification alerts', enabled: true, phase: 1 },
      { key: 'voice_call_alerts', name: 'Voice Call Alerts', description: 'Enable voice call alert delivery', enabled: true, phase: 1 },
      { key: 'coercion_mode', name: 'Coercion Mode', description: 'Enable coercion PIN functionality', enabled: true, phase: 1 },
      { key: 'test_mode', name: 'Test Mode', description: 'Enable incident simulation mode', enabled: true, phase: 1 },
      { key: 'wearable_triggers', name: 'Wearable Triggers', description: 'Enable smartwatch trigger support', enabled: false, phase: 2 },
      { key: 'disguised_interface', name: 'Disguised Interface', description: 'Enable fake calculator / disguised app mode', enabled: false, phase: 2 },
      { key: 'ai_risk_engine', name: 'AI Risk Engine', description: 'Enable ML-based risk scoring', enabled: false, phase: 2 },
      { key: 'geofencing', name: 'Geofencing', description: 'Enable geofence-based alerts', enabled: false, phase: 2 },
      { key: 'route_anomaly', name: 'Route Anomaly Detection', description: 'Enable route deviation detection', enabled: false, phase: 2 },
      { key: 'org_mode', name: 'Organization Mode', description: 'Enable campus/enterprise features', enabled: false, phase: 2 },
      { key: 'human_operators', name: 'Human Operators', description: 'Enable human-assisted response center', enabled: false, phase: 2 },
      { key: 'silent_challenge', name: 'Silent Challenge-Response', description: 'Enable silent safety check flows', enabled: false, phase: 2 },
      { key: 'evidence_export', name: 'Evidence Package Export', description: 'Enable incident evidence export', enabled: false, phase: 2 },
    ];

    for (const flag of featureFlags) {
      await queryRunner.query(
        `INSERT INTO feature_flags (key, name, description, enabled, phase)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (key) DO UPDATE SET
           name = EXCLUDED.name,
           description = EXCLUDED.description,
           phase = EXCLUDED.phase,
           updated_at = NOW()`,
        [flag.key, flag.name, flag.description, flag.enabled, flag.phase],
      );
    }
    console.log(`Feature flags seeded: ${featureFlags.length} flags.`);

    await queryRunner.commitTransaction();
    console.log('\nSeed completed successfully.');
  } catch (error) {
    await queryRunner.rollbackTransaction();
    console.error('Seed failed, transaction rolled back:', error);
    process.exit(1);
  } finally {
    await queryRunner.release();
    await dataSource.destroy();
  }
}

runSeed();

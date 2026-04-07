import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bullmq';
import { MulterModule } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { AudioController } from './audio.controller';
import { AudioService } from './audio.service';
import { AudioAsset } from './entities/audio-asset.entity';
import { Transcript } from './entities/transcript.entity';
import { DeepgramProvider } from './providers/deepgram.provider';
import { AiClassifierProvider } from './providers/ai-classifier.provider';

@Module({
  imports: [
    TypeOrmModule.forFeature([AudioAsset, Transcript]),
    BullModule.registerQueue({ name: 'audio-processing' }),
    MulterModule.register({
      storage: memoryStorage(),
    }),
  ],
  controllers: [AudioController],
  providers: [AudioService, DeepgramProvider, AiClassifierProvider],
  exports: [AudioService],
})
export class AudioModule {}

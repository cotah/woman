import {
  Controller,
  Post,
  Get,
  Param,
  Query,
  ParseUUIDPipe,
  UploadedFile,
  UseInterceptors,
  BadRequestException,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiTags,
  ApiOperation,
  ApiParam,
  ApiConsumes,
  ApiBody,
  ApiResponse,
  ApiQuery,
} from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { AudioService } from './audio.service';

const MAX_CHUNK_SIZE = 10 * 1024 * 1024; // 10 MB
const ALLOWED_MIMES = [
  'audio/webm',
  'audio/ogg',
  'audio/mp4',
  'audio/mpeg',
  'audio/wav',
  'audio/x-wav',
  'audio/aac',
];

@ApiTags('Audio')
@SkipThrottle() // Safety-critical: audio uploads during emergencies must never be blocked
@Controller('incidents')
export class AudioController {
  constructor(private readonly audioService: AudioService) {}

  /**
   * POST /incidents/:id/audio
   * Upload an audio chunk for an incident.
   */
  @Post(':id/audio')
  @HttpCode(HttpStatus.CREATED)
  @UseInterceptors(
    FileInterceptor('file', {
      limits: { fileSize: MAX_CHUNK_SIZE },
      fileFilter: (_req, file, callback) => {
        if (ALLOWED_MIMES.includes(file.mimetype)) {
          callback(null, true);
        } else {
          callback(
            new BadRequestException(
              `Unsupported audio format: ${file.mimetype}. Allowed: ${ALLOWED_MIMES.join(', ')}`,
            ),
            false,
          );
        }
      },
    }),
  )
  @ApiOperation({ summary: 'Upload an audio chunk for an incident' })
  @ApiParam({ name: 'id', description: 'Incident ID', type: 'string' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: {
        file: { type: 'string', format: 'binary', description: 'Audio file' },
        duration: {
          type: 'number',
          description: 'Duration of the audio chunk in seconds',
        },
      },
      required: ['file', 'duration'],
    },
  })
  @ApiResponse({ status: 201, description: 'Audio chunk uploaded successfully' })
  @ApiResponse({ status: 400, description: 'Invalid file or missing parameters' })
  async uploadChunk(
    @Param('id', ParseUUIDPipe) incidentId: string,
    @UploadedFile() file: Express.Multer.File,
    @Query('duration') durationStr?: string,
  ) {
    if (!file) {
      throw new BadRequestException('Audio file is required');
    }

    const duration = parseFloat(durationStr || '0');
    if (isNaN(duration) || duration < 0) {
      throw new BadRequestException('Valid duration parameter is required');
    }

    const asset = await this.audioService.uploadChunk(incidentId, file, duration);

    return {
      id: asset.id,
      incidentId: asset.incidentId,
      chunkIndex: asset.chunkIndex,
      durationSeconds: asset.durationSeconds,
      mimeType: asset.mimeType,
      sizeBytes: Number(asset.sizeBytes),
      transcriptionStatus: asset.transcriptionStatus,
      uploadedAt: asset.uploadedAt,
    };
  }

  /**
   * GET /incidents/:id/audio
   * List all audio chunks for an incident.
   */
  @Get(':id/audio')
  @ApiOperation({ summary: 'List audio chunks for an incident' })
  @ApiParam({ name: 'id', description: 'Incident ID', type: 'string' })
  @ApiResponse({ status: 200, description: 'List of audio chunks' })
  async listChunks(@Param('id', ParseUUIDPipe) incidentId: string) {
    const chunks = await this.audioService.listChunks(incidentId);

    return chunks.map((chunk) => ({
      id: chunk.id,
      chunkIndex: chunk.chunkIndex,
      durationSeconds: chunk.durationSeconds,
      mimeType: chunk.mimeType,
      sizeBytes: Number(chunk.sizeBytes),
      transcriptionStatus: chunk.transcriptionStatus,
      uploadedAt: chunk.uploadedAt,
    }));
  }

  /**
   * GET /incidents/:id/audio/:assetId/download
   * Get a pre-signed download URL for an audio chunk.
   */
  @Get(':id/audio/:assetId/download')
  @ApiOperation({ summary: 'Get a download URL for an audio chunk' })
  @ApiParam({ name: 'id', description: 'Incident ID', type: 'string' })
  @ApiParam({ name: 'assetId', description: 'Audio asset ID', type: 'string' })
  @ApiResponse({ status: 200, description: 'Pre-signed download URL' })
  async getDownloadUrl(
    @Param('id', ParseUUIDPipe) _incidentId: string,
    @Param('assetId', ParseUUIDPipe) assetId: string,
  ) {
    const url = await this.audioService.getDownloadUrl(assetId);
    return { url };
  }

  /**
   * GET /incidents/:id/transcripts
   * Get all transcripts for an incident.
   */
  @Get(':id/transcripts')
  @ApiOperation({ summary: 'List transcripts for an incident' })
  @ApiParam({ name: 'id', description: 'Incident ID', type: 'string' })
  @ApiResponse({ status: 200, description: 'List of transcripts' })
  async getTranscripts(@Param('id', ParseUUIDPipe) incidentId: string) {
    return this.audioService.getTranscripts(incidentId);
  }
}

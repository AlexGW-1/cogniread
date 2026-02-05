import {
  BadRequestException,
  Body,
  Controller,
  Inject,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../sync/sync.guard';
import type { FileStorage } from './file-storage';
import { FILE_STORAGE } from './storage.module';

type PresignRequest = {
  key?: string;
  ttlSeconds?: number;
  contentType?: string;
};

const normalizeTtl = (value?: number): number => {
  const fallback = 300;
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.max(30, Math.min(3600, Math.floor(value)));
};

const normalizeKey = (value?: string): string => {
  if (typeof value !== 'string') {
    throw new BadRequestException('key обязателен');
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw new BadRequestException('key обязателен');
  }
  return trimmed;
};

@UseGuards(JwtAuthGuard)
@Controller('storage')
export class StorageController {
  constructor(
    @Inject(FILE_STORAGE) private readonly storage: FileStorage,
  ) {}

  @Post('presign/upload')
  async presignUpload(@Body() body: PresignRequest) {
    const key = normalizeKey(body.key);
    const ttlSeconds = normalizeTtl(body.ttlSeconds);
    const presigned = await this.storage.generatePresignedUploadUrl(
      key,
      ttlSeconds,
      body.contentType,
    );
    return { key, ...presigned };
  }

  @Post('presign/download')
  async presignDownload(@Body() body: PresignRequest) {
    const key = normalizeKey(body.key);
    const ttlSeconds = normalizeTtl(body.ttlSeconds);
    const presigned = await this.storage.generatePresignedDownloadUrl(
      key,
      ttlSeconds,
    );
    return { key, ...presigned };
  }
}

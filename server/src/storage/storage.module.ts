import { Module } from '@nestjs/common';
import { FileStorage } from './file-storage';
import { GcsFileStorage } from './gcs-file-storage';
import { S3FileStorage } from './s3-file-storage';

export const FILE_STORAGE = Symbol('FILE_STORAGE');

const requireEnv = (name: string): string => {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env: ${name}`);
  }
  return value;
};

const envOr = (name: string, fallback: string): string => {
  return process.env[name] ?? fallback;
};

const buildStorage = (): FileStorage => {
  const provider = (process.env.STORAGE_PROVIDER ?? 's3').toLowerCase();
  if (provider === 's3') {
    return new S3FileStorage({
      bucket: requireEnv('S3_BUCKET'),
      region: envOr('S3_REGION', 'us-east-1'),
      endpoint: process.env.S3_ENDPOINT,
      accessKey: process.env.S3_ACCESS_KEY,
      secretKey: process.env.S3_SECRET_KEY,
    });
  }
  if (provider === 'gcs') {
    return new GcsFileStorage({
      bucket: requireEnv('GCS_BUCKET'),
      projectId: process.env.GCS_PROJECT_ID,
      keyFile: process.env.GCS_KEYFILE,
    });
  }
  throw new Error(`Unsupported STORAGE_PROVIDER: ${provider}`);
};

@Module({
  providers: [
    {
      provide: FILE_STORAGE,
      useFactory: buildStorage,
    },
  ],
  exports: [FILE_STORAGE],
})
export class StorageModule {}

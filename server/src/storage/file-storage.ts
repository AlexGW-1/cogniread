import { Readable } from 'node:stream';

export type PresignedUrl = {
  url: string;
  method: 'GET' | 'PUT';
  headers?: Record<string, string>;
  expiresAt: Date;
};

export type FileMetadata = Record<string, string>;

export interface FileStorage {
  putObject(
    key: string,
    body: Buffer | Readable,
    contentType?: string,
    metadata?: FileMetadata,
  ): Promise<void>;
  getObject(key: string): Promise<Readable>;
  deleteObject(key: string): Promise<void>;
  generatePresignedUploadUrl(
    key: string,
    ttlSeconds: number,
    contentType?: string,
  ): Promise<PresignedUrl>;
  generatePresignedDownloadUrl(
    key: string,
    ttlSeconds: number,
  ): Promise<PresignedUrl>;
}

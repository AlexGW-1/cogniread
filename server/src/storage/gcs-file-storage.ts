import { Readable } from 'node:stream';
import { Storage } from '@google-cloud/storage';
import { FileMetadata, FileStorage, PresignedUrl } from './file-storage';

export type GcsConfig = {
  bucket: string;
  projectId?: string;
  keyFile?: string;
};

export class GcsFileStorage implements FileStorage {
  private readonly storage: Storage;
  private readonly bucketName: string;

  constructor(config: GcsConfig) {
    this.bucketName = config.bucket;
    this.storage = new Storage({
      projectId: config.projectId,
      keyFilename: config.keyFile,
    });
  }

  private bucket() {
    return this.storage.bucket(this.bucketName);
  }

  async putObject(
    key: string,
    body: Buffer | Readable,
    contentType?: string,
    metadata?: FileMetadata,
  ): Promise<void> {
    const file = this.bucket().file(key);
    const stream = file.createWriteStream({
      resumable: false,
      contentType,
      metadata: metadata ? { metadata } : undefined,
    });
    await new Promise<void>((resolve, reject) => {
      stream.on('error', reject);
      stream.on('finish', () => resolve());
      if (body instanceof Readable) {
        body.pipe(stream);
        return;
      }
      stream.end(body);
    });
  }

  async getObject(key: string): Promise<Readable> {
    return this.bucket().file(key).createReadStream();
  }

  async deleteObject(key: string): Promise<void> {
    await this.bucket().file(key).delete({ ignoreNotFound: true });
  }

  async generatePresignedUploadUrl(
    key: string,
    ttlSeconds: number,
    contentType?: string,
  ): Promise<PresignedUrl> {
    const file = this.bucket().file(key);
    const [url] = await file.getSignedUrl({
      action: 'write',
      expires: Date.now() + ttlSeconds * 1000,
      contentType,
    });
    const headers = contentType ? { 'Content-Type': contentType } : undefined;
    return {
      url,
      method: 'PUT',
      headers,
      expiresAt: new Date(Date.now() + ttlSeconds * 1000),
    };
  }

  async generatePresignedDownloadUrl(
    key: string,
    ttlSeconds: number,
  ): Promise<PresignedUrl> {
    const file = this.bucket().file(key);
    const [url] = await file.getSignedUrl({
      action: 'read',
      expires: Date.now() + ttlSeconds * 1000,
    });
    return {
      url,
      method: 'GET',
      expiresAt: new Date(Date.now() + ttlSeconds * 1000),
    };
  }
}

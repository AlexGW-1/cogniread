import { Readable } from 'node:stream';
import {
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { FileMetadata, FileStorage, PresignedUrl } from './file-storage';

export type S3Config = {
  bucket: string;
  region: string;
  endpoint?: string;
  accessKey?: string;
  secretKey?: string;
};

export class S3FileStorage implements FileStorage {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor(config: S3Config) {
    this.bucket = config.bucket;
    const credentials =
      config.accessKey && config.secretKey
        ? {
            accessKeyId: config.accessKey,
            secretAccessKey: config.secretKey,
          }
        : undefined;
    this.client = new S3Client({
      region: config.region,
      endpoint: config.endpoint,
      forcePathStyle: Boolean(config.endpoint),
      credentials,
    });
  }

  async putObject(
    key: string,
    body: Buffer | Readable,
    contentType?: string,
    metadata?: FileMetadata,
  ): Promise<void> {
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: body,
        ContentType: contentType,
        Metadata: metadata,
      }),
    );
  }

  async getObject(key: string): Promise<Readable> {
    const response = await this.client.send(
      new GetObjectCommand({ Bucket: this.bucket, Key: key }),
    );
    if (!response.Body) {
      throw new Error('S3 object body is empty');
    }
    const body = response.Body;
    if (body instanceof Readable) {
      return body;
    }
    const maybeWebStream = body as { transformToWebStream?: () => ReadableStream };
    if (typeof maybeWebStream.transformToWebStream === 'function') {
      return Readable.fromWeb(maybeWebStream.transformToWebStream());
    }
    return Readable.from(body as Iterable<Uint8Array>);
  }

  async deleteObject(key: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: this.bucket, Key: key }),
    );
  }

  async generatePresignedUploadUrl(
    key: string,
    ttlSeconds: number,
    contentType?: string,
  ): Promise<PresignedUrl> {
    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: contentType,
    });
    const url = await getSignedUrl(this.client, command, {
      expiresIn: ttlSeconds,
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
    const command = new GetObjectCommand({ Bucket: this.bucket, Key: key });
    const url = await getSignedUrl(this.client, command, {
      expiresIn: ttlSeconds,
    });
    return {
      url,
      method: 'GET',
      expiresAt: new Date(Date.now() + ttlSeconds * 1000),
    };
  }
}

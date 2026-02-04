import { S3Client, CreateBucketCommand, HeadBucketCommand } from '@aws-sdk/client-s3';
import { S3FileStorage } from '../src/storage/s3-file-storage';

const shouldRun = process.env.MINIO_E2E === '1';

const describeOrSkip = shouldRun ? describe : describe.skip;

describeOrSkip('FileStorage (S3/MinIO) e2e', () => {
  const endpoint = process.env.MINIO_ENDPOINT ?? '';
  const accessKey = process.env.MINIO_ACCESS_KEY ?? '';
  const secretKey = process.env.MINIO_SECRET_KEY ?? '';
  const bucket = process.env.MINIO_BUCKET ?? '';

  if (!endpoint || !accessKey || !secretKey || !bucket) {
    throw new Error(
      'MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MINIO_BUCKET are required when MINIO_E2E=1',
    );
  }

  const client = new S3Client({
    region: 'us-east-1',
    endpoint,
    forcePathStyle: true,
    credentials: {
      accessKeyId: accessKey,
      secretAccessKey: secretKey,
    },
  });

  const storage = new S3FileStorage({
    bucket,
    region: 'us-east-1',
    endpoint,
    accessKey,
    secretKey,
  });

  beforeAll(async () => {
    try {
      await client.send(new HeadBucketCommand({ Bucket: bucket }));
    } catch {
      await client.send(new CreateBucketCommand({ Bucket: bucket }));
    }
  });

  it('uploads and downloads using presigned URLs', async () => {
    const key = `e2e/${Date.now()}-test.txt`;
    const body = 'hello-minio';

    const upload = await storage.generatePresignedUploadUrl(
      key,
      60,
      'text/plain',
    );

    const uploadRes = await fetch(upload.url, {
      method: 'PUT',
      headers: upload.headers,
      body,
    });
    expect(uploadRes.status).toBe(200);

    const download = await storage.generatePresignedDownloadUrl(key, 60);
    const downloadRes = await fetch(download.url);
    expect(downloadRes.status).toBe(200);
    const text = await downloadRes.text();
    expect(text).toBe(body);
  });
});

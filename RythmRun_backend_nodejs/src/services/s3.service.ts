import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import type { HeadObjectCommandOutput } from '@aws-sdk/client-s3';
import { getSignedUrl as getS3SignedUrl } from '@aws-sdk/s3-request-presigner';

type PresignedPutUrlInput = {
  key: string;
  contentType: string;
  sizeBytes?: number;
  expiresSeconds?: number;
};

type PresignedPutAuthorization = {
  uploadUrl: string;
  key: string;
};

type ObjectReadUrlResult = {
  url: string;
  urlExpiresAt: string;
};

type S3ServiceDependencies = {
  s3Client?: S3Client;
  presignS3Request?: typeof getS3SignedUrl;
};

export class S3Service {
  private readonly s3: S3Client;
  private readonly presignS3Request: typeof getS3SignedUrl;

  constructor(dependencies: S3ServiceDependencies = {}) {
    this.s3 =
      dependencies.s3Client ??
      new S3Client({
        region: 'auto',
        credentials: {
          accessKeyId: this.getRequiredEnv('R2_ACCESS_KEY_ID'),
          secretAccessKey: this.getRequiredEnv('R2_SECRET_ACCESS_KEY'),
        },
        endpoint: `https://${this.getRequiredEnv('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com`,
        // Presigned PUT callers supply the body later. Signing the SDK's
        // optional empty-body CRC32 would make every non-empty upload fail.
        requestChecksumCalculation: 'WHEN_REQUIRED',
      });
    this.presignS3Request = dependencies.presignS3Request ?? getS3SignedUrl;
  }

  public async getPresignedPutUrl(
    input: PresignedPutUrlInput,
  ): Promise<PresignedPutAuthorization> {
    return this.getPresignedPutUrlForBucket(
      input,
      'R2_BUCKET_ACTIVITY_IMAGES',
    );
  }

  public async getPresignedAvatarPutUrl(
    input: PresignedPutUrlInput,
  ): Promise<PresignedPutAuthorization> {
    return this.getPresignedPutUrlForBucket(input, 'R2_BUCKET_AVATARS');
  }

  private async getPresignedPutUrlForBucket(
    input: PresignedPutUrlInput,
    bucketEnvironmentVariable:
      | 'R2_BUCKET_AVATARS'
      | 'R2_BUCKET_ACTIVITY_IMAGES',
  ): Promise<PresignedPutAuthorization> {
    const command = new PutObjectCommand({
      Bucket: this.getRequiredEnv(bucketEnvironmentVariable),
      Key: input.key,
      ContentType: input.contentType,
      ContentLength: input.sizeBytes,
    });

    const signableHeaders = new Set(['content-type']);
    if (input.sizeBytes !== undefined) {
      signableHeaders.add('content-length');
    }
    const uploadUrl = await this.presignS3Request(this.s3, command, {
      expiresIn: input.expiresSeconds ?? 300,
      signableHeaders,
    });

    return {
      uploadUrl,
      key: input.key,
    };
  }

  public async getActivityImageReadUrl(
    key: string,
    expiresSeconds = 900,
  ): Promise<ObjectReadUrlResult> {
    return this.getObjectReadUrl(
      key,
      'R2_BUCKET_ACTIVITY_IMAGES',
      expiresSeconds,
    );
  }

  public async getAvatarReadUrl(
    key: string,
    expiresSeconds = 900,
  ): Promise<ObjectReadUrlResult> {
    return this.getObjectReadUrl(key, 'R2_BUCKET_AVATARS', expiresSeconds);
  }

  private async getObjectReadUrl(
    key: string,
    bucketEnvironmentVariable:
      | 'R2_BUCKET_AVATARS'
      | 'R2_BUCKET_ACTIVITY_IMAGES',
    expiresSeconds: number,
  ): Promise<ObjectReadUrlResult> {
    const command = new GetObjectCommand({
      Bucket: this.getRequiredEnv(bucketEnvironmentVariable),
      Key: key,
    });

    const url = await this.presignS3Request(this.s3, command, {
      expiresIn: expiresSeconds,
    });

    return {
      url,
      urlExpiresAt: new Date(Date.now() + expiresSeconds * 1000).toISOString(),
    };
  }

  public async headObject(
    key: string,
    bucket: string = 'R2_BUCKET_ACTIVITY_IMAGES',
  ): Promise<HeadObjectCommandOutput> {
    return this.s3.send(
      new HeadObjectCommand({
        Bucket: this.getRequiredEnv(bucket),
        Key: key,
      }),
    );
  }

  public async deleteObject(
    key: string,
    bucket: string = 'R2_BUCKET_ACTIVITY_IMAGES',
  ): Promise<void> {
    await this.s3.send(
      new DeleteObjectCommand({
        Bucket: this.getRequiredEnv(bucket),
        Key: key,
      }),
    );
  }

  private getRequiredEnv(name: string): string {
    const value = process.env[name];
    if (!value) {
      throw new Error(`${name} environment variable is required`);
    }

    return value;
  }
}

export default new S3Service();

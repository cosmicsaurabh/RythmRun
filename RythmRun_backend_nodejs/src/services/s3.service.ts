import {
  DeleteObjectCommand,
  HeadObjectCommand,
  HeadObjectCommandOutput,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl as getCloudFrontSignedUrl } from '@aws-sdk/cloudfront-signer';
import { createPresignedPost } from '@aws-sdk/s3-presigned-post';
import { getSignedUrl as getS3SignedUrl } from '@aws-sdk/s3-request-presigner';

type PresignedPutUrlInput = {
  key: string;
  contentType: string;
  expiresSeconds?: number;
};

type PresignedPutUrlResult = {
  uploadUrl: string;
  key: string;
  publicUrl: string;
};

export type PresignedPostInput = {
  key: string;
  contentType: string;
  sizeBytes: number;
  expiresSeconds?: number;
};

export type PresignedPostResult = {
  uploadUrl: string;
  fields: Record<string, string>;
  key: string;
};

type ActivityImageReadUrlResult = {
  url: string;
  urlExpiresAt: string;
};

type S3ServiceDependencies = {
  s3Client?: S3Client;
  presignS3Request?: typeof getS3SignedUrl;
  createS3PresignedPost?: typeof createPresignedPost;
  signCloudFrontUrl?: typeof getCloudFrontSignedUrl;
};

export class S3Service {
  private readonly s3: S3Client;
  private readonly presignS3Request: typeof getS3SignedUrl;
  private readonly createS3PresignedPost: typeof createPresignedPost;
  private readonly signCloudFrontUrl: typeof getCloudFrontSignedUrl;

  constructor(dependencies: S3ServiceDependencies = {}) {
    this.s3 =
      dependencies.s3Client ??
      new S3Client({
        region: process.env.AWS_REGION,
        credentials: {
          accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
          secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
        },
        // Presigned PUT callers supply the body later. Signing the SDK's
        // optional empty-body CRC32 would make every non-empty upload fail.
        requestChecksumCalculation: 'WHEN_REQUIRED',
      });
    this.presignS3Request = dependencies.presignS3Request ?? getS3SignedUrl;
    this.createS3PresignedPost =
      dependencies.createS3PresignedPost ?? createPresignedPost;
    this.signCloudFrontUrl =
      dependencies.signCloudFrontUrl ?? getCloudFrontSignedUrl;
  }

  public async getPresignedPutUrl(
    input: PresignedPutUrlInput,
  ): Promise<PresignedPutUrlResult> {
    const command = new PutObjectCommand({
      Bucket: this.getRequiredEnv('S3_BUCKET'),
      Key: input.key,
      ContentType: input.contentType,
    });

    const uploadUrl = await this.presignS3Request(this.s3, command, {
      expiresIn: input.expiresSeconds ?? 300,
      signableHeaders: new Set(['content-type']),
    });

    return {
      uploadUrl,
      key: input.key,
      publicUrl: this.getPublicUrl(input.key),
    };
  }

  public async getPresignedPost(
    input: PresignedPostInput,
  ): Promise<PresignedPostResult> {
    const post = await this.createS3PresignedPost(this.s3, {
      Bucket: this.getRequiredEnv('S3_BUCKET'),
      Key: input.key,
      Fields: {
        key: input.key,
        'Content-Type': input.contentType,
      },
      Conditions: [
        ['eq', '$key', input.key],
        ['eq', '$Content-Type', input.contentType],
        ['content-length-range', input.sizeBytes, input.sizeBytes],
      ],
      Expires: input.expiresSeconds ?? 300,
    });

    return {
      uploadUrl: post.url,
      fields: { ...post.fields },
      key: input.key,
    };
  }

  public getPublicUrl(key: string): string {
    return `https://${this.getRequiredEnv('CLOUDFRONT_DOMAIN')}/${key}`;
  }

  public getActivityImageReadUrl(
    key: string,
    expiresSeconds = 900,
  ): ActivityImageReadUrlResult {
    const expiresAt = new Date(Date.now() + expiresSeconds * 1000);
    const signingExpiresAt = new Date(
      Math.floor(expiresAt.getTime() / 1000) * 1000,
    );
    const url = this.signCloudFrontUrl({
      url: this.getPublicUrl(key),
      keyPairId: this.getRequiredEnv('CLOUDFRONT_KEY_PAIR_ID'),
      privateKey: this.getRequiredEnv('CLOUDFRONT_PRIVATE_KEY').replace(
        /\\n/g,
        '\n',
      ),
      dateLessThan: signingExpiresAt,
    });

    return {
      url,
      urlExpiresAt: expiresAt.toISOString(),
    };
  }

  public async headObject(key: string): Promise<HeadObjectCommandOutput> {
    return this.s3.send(
      new HeadObjectCommand({
        Bucket: this.getRequiredEnv('S3_BUCKET'),
        Key: key,
      }),
    );
  }

  public async deleteObject(key: string): Promise<void> {
    await this.s3.send(
      new DeleteObjectCommand({
        Bucket: this.getRequiredEnv('S3_BUCKET'),
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

import AWS from 'aws-sdk';
import { v4 as uuid } from 'uuid';

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

type ActivityImageReadUrlResult = {
  url: string;
  urlExpiresAt: string;
};

class S3Service {
  private s3: AWS.S3;

  constructor() {
    this.s3 = new AWS.S3({
      region: process.env.AWS_REGION,
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID!,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY!,
      },
      signatureVersion: 'v4',
    });
  }

  public async getPresignedPutUrl(
    input: PresignedPutUrlInput,
  ): Promise<PresignedPutUrlResult> {
    const params = {
      Bucket: this.getRequiredEnv('S3_BUCKET'),
      Key: input.key,
      ContentType: input.contentType,
      Expires: input.expiresSeconds ?? 300,
    };

    const uploadUrl = await this.s3.getSignedUrlPromise('putObject', params);

    return {
      uploadUrl,
      key: input.key,
      publicUrl: this.getPublicUrl(input.key),
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
    const signer = new AWS.CloudFront.Signer(
      this.getRequiredEnv('CLOUDFRONT_KEY_PAIR_ID'),
      this.getRequiredEnv('CLOUDFRONT_PRIVATE_KEY').replace(/\\n/g, '\n'),
    );

    const url = signer.getSignedUrl({
      url: this.getPublicUrl(key),
      expires: Math.floor(expiresAt.getTime() / 1000),
    });

    return {
      url,
      urlExpiresAt: expiresAt.toISOString(),
    };
  }

  public async headObject(key: string): Promise<AWS.S3.HeadObjectOutput> {
    return this.s3
      .headObject({
        Bucket: this.getRequiredEnv('S3_BUCKET'),
        Key: key,
      })
      .promise();
  }

  public async deleteObject(key: string): Promise<void> {
    await this.s3
      .deleteObject({
        Bucket: this.getRequiredEnv('S3_BUCKET'),
        Key: key,
      })
      .promise();
  }

  public async getUploadUrl(userId: number, ext: string, contentType: string) {
    const key = `avatars/${userId}/${uuid()}.${ext}`;

    return this.getPresignedPutUrl({ key, contentType });
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

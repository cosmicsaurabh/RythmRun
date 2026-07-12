import { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { v4 as uuid } from 'uuid';

class S3Service {
  private s3Client: S3Client;
  private bucket: string;
  private r2PublicUrl: string;

  constructor() {
    this.bucket = process.env.R2_BUCKET_AVATARS || 'avatars';
    this.r2PublicUrl = process.env.R2_PUBLIC_URL || 'https://your-account.r2.cloudflarestorage.com';

    this.s3Client = new S3Client({
      region: 'auto',
      credentials: {
        accessKeyId: process.env.R2_ACCESS_KEY_ID!,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
      },
      endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    });
  }

  public async getUploadUrl(userId: number, ext: string, contentType: string) {
    const key = `avatars/${userId}/${uuid()}.${ext}`;

    const command = new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      ContentType: contentType,
    });

    const uploadUrl = await getSignedUrl(this.s3Client, command, { expiresIn: 300 }); // 5 minutes

    return {
      uploadUrl,
      key,
      publicUrl: `${this.r2PublicUrl}/${key}`,
    };
  }

  public async getSignedReadUrl(key: string, expiresIn: number = 900): Promise<string> {
    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: key,
    });

    return await getSignedUrl(this.s3Client, command, { expiresIn });
  }

  public async deleteObject(key: string): Promise<void> {
    const command = new DeleteObjectCommand({
      Bucket: this.bucket,
      Key: key,
    });

    await this.s3Client.send(command);
  }
}

export default new S3Service();

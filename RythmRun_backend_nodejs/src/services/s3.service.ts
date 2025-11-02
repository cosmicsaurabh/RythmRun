import AWS from 'aws-sdk';
import { v4 as uuid } from 'uuid';

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

  public async getUploadUrl(userId: number, ext: string, contentType: string) {
    const key = `avatars/${userId}/${uuid()}.${ext}`;

    const params = {
      Bucket: process.env.S3_BUCKET,
      Key: key,
      ContentType: contentType,
      Expires: 300, // 5 minutes
    };

    const uploadUrl = await this.s3.getSignedUrlPromise('putObject', params);

    return {
      uploadUrl,
      key,
      publicUrl: `https://${process.env.CLOUDFRONT_DOMAIN}/${key}`,
    };
  }
}

export default new S3Service();

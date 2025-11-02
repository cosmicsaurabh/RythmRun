import { Request, Response } from 'express';
import s3Service from '../services/s3.service';
import { PrismaClient } from '../../generated/prisma/index.js';

const prisma = new PrismaClient();

class AvatarController {
  public async getUploadUrl(req: Request, res: Response) {
    try {
      const userId = (req as any).user.id;
      const { ext, contentType } = req.body;

      if (!ext || !contentType) {
        return res.status(400).json({ message: 'ext and contentType are required' });
      }
      
      const result = await s3Service.getUploadUrl(userId, ext, contentType);

      res.json(result);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error generating upload URL' });
    }
  }

  public async confirmUpload(req: Request, res: Response) {
    try {
      const userId = (req as any).user.id;
      const { key, contentType } = req.body;

      if (!key || !contentType) {
        return res.status(400).json({ message: 'key and contentType are required' });
      }

      await prisma.user.update({
        where: { id: userId },
        data: {
          profilePicturePath: key,
          profilePictureType: contentType,
        },
      });

      res.sendStatus(200);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error confirming upload' });
    }
  }
}

export default new AvatarController();

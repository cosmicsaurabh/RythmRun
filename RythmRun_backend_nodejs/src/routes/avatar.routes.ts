import { Router } from 'express';
import { container } from '../config/container';
import { AvatarController } from '../controllers/avatar.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();
const avatarController = container.resolve(AvatarController);

router.post('/upload-url', authMiddleware, avatarController.getUploadUrl);
router.post('/confirm', authMiddleware, avatarController.confirmUpload);

export default router;

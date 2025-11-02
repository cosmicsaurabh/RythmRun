import { Router } from 'express';
import avatarController from '../controllers/avatar.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.post('/upload-url', authMiddleware, avatarController.getUploadUrl);
router.post('/confirm', authMiddleware, avatarController.confirmUpload);

export default router;

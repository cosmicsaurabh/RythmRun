import { Router } from 'express';
import { container } from '../config/container';
import { ActivityImageController } from '../controllers/activity-image.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router({ mergeParams: true });
const activityImageController = container.resolve(ActivityImageController);

router.get('/', authMiddleware, activityImageController.listImages);
router.post(
  '/upload-url',
  authMiddleware,
  activityImageController.requestUploadUrl,
);
router.post('/confirm', authMiddleware, activityImageController.confirmUpload);
router.delete('/:imageId', authMiddleware, activityImageController.deleteImage);

export default router;

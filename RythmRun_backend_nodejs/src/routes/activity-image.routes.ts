import { Router } from 'express';
import { container } from '../config/container.js';
import { ActivityImageController } from '../controllers/activity-image.controller.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

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

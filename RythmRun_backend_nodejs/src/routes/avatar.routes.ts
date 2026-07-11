import { RequestHandler, Router } from 'express';
import { container } from '../config/container';
import { AvatarController } from '../controllers/avatar.controller';
import { authMiddleware } from '../middleware/auth.middleware';

export interface AvatarRouteController {
  getUploadUrl: RequestHandler;
  confirmUpload: RequestHandler;
}

export interface AvatarRouterDependencies {
  controller: AvatarRouteController;
  authenticate: RequestHandler;
}

/** Builds the avatar router without resolving storage or database clients. */
export function createAvatarRouter({
  controller,
  authenticate,
}: AvatarRouterDependencies): Router {
  const router = Router();

  router.post('/upload-url', authenticate, controller.getUploadUrl);
  router.post('/confirm', authenticate, controller.confirmUpload);

  return router;
}

const router = createAvatarRouter({
  controller: container.resolve(AvatarController),
  authenticate: authMiddleware,
});

export default router;

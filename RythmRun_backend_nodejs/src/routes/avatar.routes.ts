import { Router } from 'express';
import type { RequestHandler } from 'express';
import { container } from '../config/container.js';
import { AvatarController } from '../controllers/avatar.controller.js';
import { authMiddleware } from '../middleware/auth.middleware.js';

export interface AvatarRouteController {
  getUploadUrl: RequestHandler;
  confirmUpload: RequestHandler;
  getReadUrl: RequestHandler;
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
  router.get('/read-url', authenticate, controller.getReadUrl);

  return router;
}

const router = createAvatarRouter({
  controller: container.resolve(AvatarController),
  authenticate: authMiddleware,
});

export default router;

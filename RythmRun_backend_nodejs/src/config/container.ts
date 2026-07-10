import "reflect-metadata";
import { container } from "tsyringe";
import { PrismaClient } from '../../generated/prisma';
import { UserService } from '../services/user.service';
import { ActivityService } from '../services/activity.service';
import { ActivityImageService } from '../services/activity-image.service';
import { CommentService } from '../services/comment.service';
import { LikeService } from '../services/like.service';
import { FriendService } from '../services/friend.service';
import { AvatarService } from '../services/avatar.service';
import s3Service from '../services/s3.service';

// Register Prisma as a singleton
container.registerInstance("PrismaClient", new PrismaClient());
container.registerInstance("S3Service", s3Service);

// Register all services
container.register("UserService", {
    useClass: UserService
});

container.register("ActivityService", {
    useClass: ActivityService
});

container.register("ActivityImageService", {
    useClass: ActivityImageService
});

container.register("CommentService", {
    useClass: CommentService
});

container.register("LikeService", {
    useClass: LikeService
});

container.register("FriendService", {
    useClass: FriendService
});

container.register("AvatarService", {
    useClass: AvatarService
});

export { container };

import "reflect-metadata";
import { container } from "tsyringe";
import { PrismaClient } from '../../generated/prisma';
import { UserService } from '../services/user.service';
import { ActivityService } from '../services/activity.service';
import { CommentService } from '../services/comment.service';
import { LikeService } from '../services/like.service';
import { FriendService } from '../services/friend.service';

// Register Prisma as a singleton
container.registerInstance("PrismaClient", new PrismaClient());

// Register all services
container.register("UserService", {
    useClass: UserService
});

container.register("ActivityService", {
    useClass: ActivityService
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

export { container }; 
import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class CreateCommentDto {
    @IsNotEmpty()
    @IsString()
    @MaxLength(1000, { message: 'Comment cannot be longer than 1000 characters' })
    content!: string;
}

export class CommentResponseDto {
    id?: number;
    activityId?: number;
    userId?: number;
    content?: string;
    createdAt?: Date;
    updatedAt?: Date;
    user?: {
        id: number;
        username: string;
        firstname?: string;
        lastname?: string;
        profilePicture?: Buffer;
        profilePictureType?: string;
    };
} 
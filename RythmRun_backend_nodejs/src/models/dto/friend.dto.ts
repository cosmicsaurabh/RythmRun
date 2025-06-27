import { IsNotEmpty, IsNumber } from 'class-validator';

export class SendFriendRequestDto {
    @IsNotEmpty()
    @IsNumber()
    targetUserId!: number;
}

export class FriendResponseDto {
    id?: number;
    user1Id?: number;
    user2Id?: number;
    status?: string;
    createdAt?: Date;
    updatedAt?: Date;
    user1?: {
        id: number;
        username: string;
        firstname?: string;
        lastname?: string;
        profilePicture?: Buffer;
        profilePictureType?: string;
    };
    user2?: {
        id: number;
        username: string;
        firstname?: string;
        lastname?: string;
        profilePicture?: Buffer;
        profilePictureType?: string;
    };
} 
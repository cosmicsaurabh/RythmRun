import { Request, Response } from 'express';
import { UserService } from '../services/user.service';
import { RegisterUserDto, LoginUserDto, ChangePasswordDto, UpdateProfileDto } from '../models/dto/user.dto';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';
import { injectable, inject } from "tsyringe";
import { validateDto } from '../middleware/validation.middleware';
import path from 'path';
import { UPLOAD_DIRECTORY } from '../config/upload.config';
import { deleteFile } from '../middleware/file-upload.middleware';
import fs from 'fs';

@injectable()
export class UserController {
    constructor(
        @inject("UserService") private userService: UserService
    ) {}

    register = async (req: Request, res: Response) => {
        try {
            const registerDto = await validateDto(RegisterUserDto, req.body);
            const result = await this.userService.register(registerDto);
            res.status(201).json(result);
        } catch (error: any) {
            res.status(400).json({
                error: 'REGISTRATION_FAILED',
                message: error.message,
                statusCode: 400,
                timestamp: new Date().toISOString()
            });
        }
    };

    login = async (req: Request, res: Response) => {
        try {
            const loginDto = await validateDto(LoginUserDto, req.body);
            const result = await this.userService.login(loginDto);
            res.status(200).json(result);
        } catch (error: any) {
            res.status(401).json({
                error: 'LOGIN_FAILED',
                message: error.message,
                statusCode: 401,
                timestamp: new Date().toISOString()
            });
        }
    };

    logout = async (req: Request, res: Response) => {
        try {
            await this.userService.logout(req.user!.id);
            return res.status(200).json({
                status: 'success',
                message: 'Successfully logged out'
            });
        } catch (error) {
            console.error('Logout error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    refreshToken = async (req: Request, res: Response) => {
        try {
            const result = await this.userService.refreshToken(
                req.user!.id,
                req.body.refreshToken
            );

            return res.status(200).json({
                status: 'success',
                data: result
            });
        } catch (error: any) {
            if (error?.message === 'Invalid refresh token') {
                return res.status(401).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Token refresh error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    changePassword = async (req: Request, res: Response) => {
        try {
            const userId = (req as any).user.userId;
            const changePasswordDto = await validateDto(ChangePasswordDto, req.body);
            await this.userService.changePassword(userId, changePasswordDto);
            res.status(200).json({ message: 'Password changed successfully' });
        } catch (error: any) {
            res.status(400).json({
                error: 'PASSWORD_CHANGE_FAILED',
                message: error.message,
                statusCode: 400,
                timestamp: new Date().toISOString()
            });
        }
    };

    updateProfile = async (req: Request, res: Response) => {
        try {
            const userId = (req as any).user.userId;
            const updateProfileDto = await validateDto(UpdateProfileDto, req.body);
            await this.userService.updateProfile(userId, updateProfileDto);
            res.status(200).json({ message: 'Profile updated successfully' });
        } catch (error: any) {
            res.status(400).json({
                error: 'PROFILE_UPDATE_FAILED',
                message: error.message,
                statusCode: 400,
                timestamp: new Date().toISOString()
            });
        }
    };

    uploadProfilePicture = async (req: Request, res: Response) => {
        try {
            const userId = (req as any).user.userId;
            if (!req.file) {
                return res.status(400).json({
                    error: 'FILE_REQUIRED',
                    message: 'No file uploaded',
                    statusCode: 400,
                    timestamp: new Date().toISOString()
                });
            }

            // Get the current user to check existing profile picture
            const currentUser = await this.userService.findById(userId);
            if (currentUser.profilePicturePath) {
                // Delete old profile picture if it exists
                await deleteFile(path.join(UPLOAD_DIRECTORY, currentUser.profilePicturePath));
            }
            
            // Update the profile picture path in the database
            await this.userService.updateProfilePicture(userId, {
                profilePicturePath: req.file.filename,
                profilePictureType: req.file.mimetype
            });

            res.status(200).json({ 
                message: 'Profile picture updated successfully',
                filename: req.file.filename
            });
        } catch (error: any) {
            // If there's an error, make sure to clean up the uploaded file
            if (req.file) {
                await deleteFile(path.join(UPLOAD_DIRECTORY, req.file.filename));
            }

            res.status(400).json({
                error: 'PROFILE_PICTURE_UPDATE_FAILED',
                message: error.message,
                statusCode: 400,
                timestamp: new Date().toISOString()
            });
        }
    };

    getProfilePicture = async (req: Request, res: Response) => {
        try {
            const userId = parseInt(req.params.id);
            const user = await this.userService.findById(userId);
            
            if (!user || !user.profilePicturePath) {
                return res.status(404).json({
                    error: 'NOT_FOUND',
                    message: 'Profile picture not found',
                    statusCode: 404,
                    timestamp: new Date().toISOString()
                });
            }

            const filePath = path.join(UPLOAD_DIRECTORY, user.profilePicturePath);
            
            // Check if file exists
            if (!fs.existsSync(filePath)) {
                return res.status(404).json({
                    error: 'NOT_FOUND',
                    message: 'Profile picture file not found',
                    statusCode: 404,
                    timestamp: new Date().toISOString()
                });
            }

            res.setHeader('Content-Type', user.profilePictureType || 'image/jpeg');
            res.sendFile(filePath);
        } catch (error: any) {
            res.status(500).json({
                error: 'PROFILE_PICTURE_FETCH_FAILED',
                message: error.message,
                statusCode: 500,
                timestamp: new Date().toISOString()
            });
        }
    };
} 
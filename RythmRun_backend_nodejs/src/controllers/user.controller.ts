import { Request, Response } from 'express';
import { UserService } from '../services/user.service';
import { RegisterUserDto, LoginUserDto, ChangePasswordDto } from '../models/dto/user.dto';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';

export class UserController {
    private userService: UserService;

    constructor() {
        this.userService = new UserService();
    }

    register = async (req: Request, res: Response) => {
        try {
            // Transform request body to DTO
            const registerDto = plainToClass(RegisterUserDto, req.body);

            // Validate DTO
            const errors = await validate(registerDto);
            if (errors.length > 0) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid input',
                    errors: errors.map(error => ({
                        property: error.property,
                        constraints: error.constraints
                    }))
                });
            }

            // Register user
            const result = await this.userService.register(registerDto);

            return res.status(201).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Username already exists') {
                return res.status(409).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Registration error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };

    login = async (req: Request, res: Response) => {
        try {
            // Transform request body to DTO
            const loginDto = plainToClass(LoginUserDto, req.body);

            // Validate DTO
            const errors = await validate(loginDto);
            if (errors.length > 0) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid input',
                    errors: errors.map(error => ({
                        property: error.property,
                        constraints: error.constraints
                    }))
                });
            }

            // Login user
            const result = await this.userService.login(loginDto);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Invalid username or password') {
                return res.status(401).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Login error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
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
            // Transform request body to DTO
            const changePasswordDto = plainToClass(ChangePasswordDto, req.body);

            // Validate DTO
            const errors = await validate(changePasswordDto);
            if (errors.length > 0) {
                return res.status(400).json({
                    status: 'error',
                    message: 'Invalid input',
                    errors: errors.map(error => ({
                        property: error.property,
                        constraints: error.constraints
                    }))
                });
            }

            // Change password
            const result = await this.userService.changePassword(req.user!.id, changePasswordDto);

            return res.status(200).json({
                status: 'success',
                data: result
            });

        } catch (error: any) {
            if (error?.message === 'Current password is incorrect') {
                return res.status(401).json({
                    status: 'error',
                    message: error.message
                });
            }

            console.error('Password change error:', error);
            return res.status(500).json({
                status: 'error',
                message: 'Internal server error'
            });
        }
    };
} 
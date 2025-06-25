import { Request, Response } from 'express';
import { UserService } from '../services/user.service';
import { RegisterUserDto } from '../models/dto/user.dto';
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
            const user = await this.userService.register(registerDto);

            return res.status(201).json({
                status: 'success',
                data: user
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
} 
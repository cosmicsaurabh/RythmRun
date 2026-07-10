import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { PrismaClient } from '../../generated/prisma';
import { getJwtSecrets } from '../config/env';

// Extend Express Request type to include user
declare global {
    namespace Express {
        interface Request {
            user?: {
                id: number;
            }
        }
    }
}

export const authMiddleware = (req: Request, res: Response, next: NextFunction) => {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return res.status(401).json({
                status: 'error',
                message: 'No token provided'
            });
        }

        const token = authHeader.split(' ')[1];
        
        // Verify token
        const decoded = jwt.verify(token, getJwtSecrets().accessSecret) as {
            userId: number;
        };

        // Add user info to request
        req.user = { id: decoded.userId };
        next();
    } catch (error) {
        return res.status(401).json({
            status: 'error',
            message: 'Invalid token'
        });
    }
};

export const refreshTokenMiddleware = async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { refreshToken } = req.body;
        if (!refreshToken) {
            return res.status(401).json({
                status: 'error',
                message: 'No refresh token provided'
            });
        }

        const prisma = new PrismaClient();

        // Verify token exists and is not expired
        const storedToken = await prisma.refreshToken.findFirst({
            where: {
                token: refreshToken,
                expiryDate: {
                    gt: new Date()
                }
            },
            include: {
                user: true
            }
        });

        if (!storedToken) {
            return res.status(401).json({
                status: 'error',
                message: 'Invalid or expired refresh token'
            });
        }

        try {
            // Verify token signature
            const decoded = jwt.verify(refreshToken, getJwtSecrets().refreshSecret) as {
                userId: number;
            };

            // Verify token matches the stored user
            if (decoded.userId !== storedToken.userId) {
                return res.status(401).json({
                    status: 'error',
                    message: 'Invalid refresh token'
                });
            }

            req.user = { id: decoded.userId };
            next();
        } catch (error) {
            return res.status(401).json({
                status: 'error',
                message: 'Invalid refresh token'
            });
        }
    } catch (error) {
        console.error(
            'Refresh token middleware failed',
            error instanceof Error ? error.name : 'UnknownError'
        );
        return res.status(500).json({
            status: 'error',
            message: 'Internal server error'
        });
    }
};

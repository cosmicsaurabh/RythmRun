import { Request, Response, NextFunction } from 'express';
import multer from 'multer';
import fs from 'fs';
import { uploadConfig, UPLOAD_DIRECTORY } from '../config/upload.config';

// Ensure upload directory exists
if (!fs.existsSync(UPLOAD_DIRECTORY)) {
  fs.mkdirSync(UPLOAD_DIRECTORY, { recursive: true });
}

// Create multer instance with our configuration
const upload = multer(uploadConfig);

// Middleware for handling single file uploads
export const uploadSingleFile = (fieldName: string) => {
  return (req: Request, res: Response, next: NextFunction) => {
    upload.single(fieldName)(req, res, (err: any) => {
      if (err instanceof multer.MulterError) {
        // Multer-specific errors
        if (err.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({
            error: 'FILE_TOO_LARGE',
            message: 'File size exceeds the 10MB limit',
            statusCode: 400,
            timestamp: new Date().toISOString()
          });
        }
        return res.status(400).json({
          error: 'UPLOAD_ERROR',
          message: err.message,
          statusCode: 400,
          timestamp: new Date().toISOString()
        });
      } else if (err) {
        // Other errors (like invalid file type)
        return res.status(400).json({
          error: 'INVALID_FILE',
          message: err.message,
          statusCode: 400,
          timestamp: new Date().toISOString()
        });
      }
      next();
    });
  };
};

// Helper function to delete a file
export const deleteFile = async (filePath: string): Promise<void> => {
  try {
    await fs.promises.unlink(filePath);
  } catch (error) {
    console.error(`Error deleting file ${filePath}:`, error);
  }
}; 
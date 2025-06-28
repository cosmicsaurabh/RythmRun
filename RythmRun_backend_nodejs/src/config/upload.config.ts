import { Request } from 'express';
import multer from 'multer';
import path from 'path';
import crypto from 'crypto';

// Constants
export const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB
export const ALLOWED_FILE_TYPES = ['image/jpeg', 'image/png', 'image/gif'];
export const UPLOAD_DIRECTORY = path.join(process.cwd(), 'uploads');

// Custom storage configuration
const storage = multer.diskStorage({
  destination: (_req: Request, _file: Express.Multer.File, cb) => {
    cb(null, UPLOAD_DIRECTORY);
  },
  filename: (_req: Request, file: Express.Multer.File, cb) => {
    // Generate a random filename while keeping the original extension
    const randomName = crypto.randomBytes(16).toString('hex');
    const extension = path.extname(file.originalname);
    cb(null, `${randomName}${extension}`);
  }
});

// File filter function
const fileFilter = (_req: Request, file: Express.Multer.File, cb: multer.FileFilterCallback) => {
  if (ALLOWED_FILE_TYPES.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type. Only JPEG, PNG and GIF images are allowed.'));
  }
};

// Export multer configuration
export const uploadConfig = {
  storage,
  fileFilter,
  limits: {
    fileSize: MAX_FILE_SIZE
  }
}; 
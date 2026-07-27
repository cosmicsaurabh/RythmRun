import type { Request, Response } from 'express';
import { inject, injectable } from 'tsyringe';
import { DtoValidationError, validateDto } from '../middleware/validation.middleware.js';
import {
  ConfirmAvatarUploadDto,
  RequestAvatarUploadDto,
} from '../models/dto/avatar.dto.js';
import { AvatarService, AvatarServiceError } from '../services/avatar.service.js';

@injectable()
export class AvatarController {
  constructor(
    @inject('AvatarService') private avatarService: AvatarService,
  ) {}

  getUploadUrl = async (req: Request, res: Response) => {
    try {
      const dto = await validateDto(RequestAvatarUploadDto, req.body);
      const result = await this.avatarService.requestUpload(req.user!.id, dto);
      return res.status(200).json(result);
    } catch (error) {
      return this.handleError(error, res);
    }
  };

  confirmUpload = async (req: Request, res: Response) => {
    try {
      const dto = await validateDto(ConfirmAvatarUploadDto, req.body);
      const result = await this.avatarService.confirmUpload(req.user!.id, dto);
      return res.status(200).json(result);
    } catch (error) {
      return this.handleError(error, res);
    }
  };

  getReadUrl = async (req: Request, res: Response) => {
    try {
      const result = await this.avatarService.getReadUrl(req.user!.id);
      return res.status(200).json(result);
    } catch (error) {
      return this.handleError(error, res);
    }
  };

  private handleError(error: unknown, res: Response) {
    if (error instanceof DtoValidationError) {
      return res.status(400).json({ message: error.message });
    }

    if (error instanceof AvatarServiceError) {
      return res.status(error.statusCode).json({ message: error.message });
    }

    console.error(
      'Avatar endpoint failed',
      error instanceof Error ? error.name : 'UnknownError',
    );
    return res.status(500).json({ message: 'Avatar request failed' });
  }
}

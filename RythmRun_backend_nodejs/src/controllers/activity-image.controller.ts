import type { Request, Response } from 'express';
import { plainToClass } from 'class-transformer';
import { validate } from 'class-validator';
import { injectable, inject } from 'tsyringe';
import { ActivityImageServiceError } from '../errors/activity-image.error.js';
import { ActivityImageService } from '../services/activity-image.service.js';
import {
  ConfirmActivityImageUploadDto,
  RequestActivityImageUploadUrlDto,
} from '../models/dto/activity-image.dto.js';

@injectable()
export class ActivityImageController {
  constructor(
    @inject('ActivityImageService')
    private activityImageService: ActivityImageService,
  ) {}

  listImages = async (req: Request, res: Response) => {
    try {
      const activityId = this.parseActivityId(req, res);
      if (activityId == null) return;

      const result = await this.activityImageService.listImages(
        req.user!.id,
        activityId,
      );

      return res.status(200).json({
        status: 'success',
        data: result,
      });
    } catch (error: any) {
      return this.handleError(error, res, 'List activity images error');
    }
  };

  requestUploadUrl = async (req: Request, res: Response) => {
    try {
      const activityId = this.parseActivityId(req, res);
      if (activityId == null) return;

      const dto = plainToClass(RequestActivityImageUploadUrlDto, req.body);
      const isValid = await this.validateDto(dto, res);
      if (!isValid) return;

      const result = await this.activityImageService.requestUploadUrl(
        req.user!.id,
        activityId,
        dto,
      );

      return res.status(200).json({
        status: 'success',
        data: result,
      });
    } catch (error: any) {
      return this.handleError(error, res, 'Request image upload URL error');
    }
  };

  confirmUpload = async (req: Request, res: Response) => {
    try {
      const activityId = this.parseActivityId(req, res);
      if (activityId == null) return;

      const dto = plainToClass(ConfirmActivityImageUploadDto, req.body);
      const isValid = await this.validateDto(dto, res);
      if (!isValid) return;

      const result = await this.activityImageService.confirmUpload(
        req.user!.id,
        activityId,
        dto,
      );

      return res.status(200).json({
        status: 'success',
        data: result,
      });
    } catch (error: any) {
      return this.handleError(error, res, 'Confirm image upload error');
    }
  };

  deleteImage = async (req: Request, res: Response) => {
    try {
      const activityId = this.parseActivityId(req, res);
      if (activityId == null) return;

      const imageId = parseInt(req.params.imageId as string);
      if (isNaN(imageId)) {
        return res.status(400).json({
          status: 'error',
          message: 'Invalid image ID',
        });
      }

      const result = await this.activityImageService.deleteImage(
        req.user!.id,
        activityId,
        imageId,
      );

      return res.status(200).json({
        status: 'success',
        data: result,
      });
    } catch (error: any) {
      return this.handleError(error, res, 'Delete activity image error');
    }
  };

  private parseActivityId(req: Request, res: Response): number | null {
    const activityId = parseInt(req.params.activityId as string);
    if (isNaN(activityId)) {
      res.status(400).json({
        status: 'error',
        message: 'Invalid activity ID',
      });
      return null;
    }

    return activityId;
  }

  private async validateDto(
    dto: RequestActivityImageUploadUrlDto | ConfirmActivityImageUploadDto,
    res: Response,
  ): Promise<boolean> {
    const errors = await validate(dto, {
      forbidUnknownValues: true,
      whitelist: true,
    });

    if (errors.length === 0) {
      return true;
    }

    res.status(400).json({
      status: 'error',
      message: 'Invalid input',
      errors: errors.map((error) => ({
        property: error.property,
        constraints: error.constraints,
      })),
    });

    return false;
  }

  private handleError(error: any, res: Response, logMessage: string) {
    // IP-2.6 item 4: the status and stable code travel with the error, so a
    // reworded message can no longer silently turn a 400 into a 500.
    if (error instanceof ActivityImageServiceError) {
      return res.status(error.statusCode).json({
        status: 'error',
        code: error.code,
        message: error.message,
      });
    }

    // Log the category only. The error object can carry a presigned URL, an
    // object key, or a driver payload, none of which belong in the log.
    const category = error instanceof Error ? error.name : 'UnknownError';
    console.error(`${logMessage} (${category})`);
    return res.status(500).json({
      status: 'error',
      message: 'Internal server error',
    });
  }
}

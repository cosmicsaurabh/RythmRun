import { ClassConstructor, plainToClass } from 'class-transformer';
import { validate } from 'class-validator';

export async function validateDto<T extends object>(
    dtoClass: ClassConstructor<T>,
    plainObject: object
): Promise<T> {
    // Transform plain object to DTO instance
    const dto = plainToClass(dtoClass, plainObject);

    // Validate DTO
    const errors = await validate(dto);
    if (errors.length > 0) {
        const errorMessages = errors.map(error => ({
            property: error.property,
            constraints: error.constraints
        }));
        throw new Error(`Validation failed: ${JSON.stringify(errorMessages)}`);
    }

    return dto;
} 
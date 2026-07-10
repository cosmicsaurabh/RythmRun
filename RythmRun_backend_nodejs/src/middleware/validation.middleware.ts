import { ClassConstructor, plainToInstance } from 'class-transformer';
import { validate, ValidationError } from 'class-validator';

export interface DtoValidationIssue {
    property: string;
    constraints: string[];
}

export class DtoValidationError extends Error {
    readonly issues: DtoValidationIssue[];

    constructor(issues: DtoValidationIssue[]) {
        // Keep request values out of controller responses and logs.
        super('Validation failed');
        this.name = 'DtoValidationError';
        this.issues = issues;
        Object.setPrototypeOf(this, DtoValidationError.prototype);
    }
}

const FORBIDDEN_PROPERTY_NAMES = new Set(['__proto__', 'constructor', 'prototype']);

function isPlainObject(value: unknown): value is Record<string, unknown> {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
        return false;
    }

    const prototype = Object.getPrototypeOf(value);
    return prototype === Object.prototype || prototype === null;
}

function containsForbiddenPropertyName(value: unknown, visited = new WeakSet<object>()): boolean {
    if (typeof value !== 'object' || value === null || visited.has(value)) {
        return false;
    }

    visited.add(value);

    for (const property of Object.keys(value)) {
        if (FORBIDDEN_PROPERTY_NAMES.has(property)) {
            return true;
        }

        // Inspect data properties without invoking an attacker-controlled getter.
        const descriptor = Object.getOwnPropertyDescriptor(value, property);
        if (descriptor && 'value' in descriptor && containsForbiddenPropertyName(descriptor.value, visited)) {
            return true;
        }
    }

    return false;
}

function toValidationIssues(errors: ValidationError[], parent = ''): DtoValidationIssue[] {
    return errors.flatMap(error => {
        const property = parent ? `${parent}.${error.property}` : error.property;
        const currentIssue = error.constraints
            ? [{ property, constraints: Object.values(error.constraints) }]
            : [];

        return [
            ...currentIssue,
            ...toValidationIssues(error.children ?? [], property)
        ];
    });
}

export async function validateDto<T extends object>(
    dtoClass: ClassConstructor<T>,
    plainObject: unknown
): Promise<T> {
    if (!isPlainObject(plainObject)) {
        throw new DtoValidationError([{
            property: '$root',
            constraints: ['request body must be a plain object']
        }]);
    }

    if (containsForbiddenPropertyName(plainObject)) {
        throw new DtoValidationError([{
            property: '$root',
            constraints: ['request body contains a forbidden property name']
        }]);
    }

    const dto = plainToInstance(dtoClass, plainObject);

    const errors = await validate(dto, {
        whitelist: true,
        forbidNonWhitelisted: true,
        forbidUnknownValues: true,
        validationError: {
            target: false,
            value: false
        }
    });

    if (errors.length > 0) {
        throw new DtoValidationError(toValidationIssues(errors));
    }

    return dto;
}

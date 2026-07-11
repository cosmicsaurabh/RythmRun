import { ClassConstructor, plainToInstance } from 'class-transformer';
import { validate, ValidationError } from 'class-validator';

export interface DtoValidationIssue {
    property: string;
    constraintCodes: string[];
    constraints: string[];
}

export const MAX_DTO_VALIDATION_ISSUES = 25;
export const MAX_DTO_ISSUE_PATH_LENGTH = 160;
export const MAX_DTO_ISSUE_MESSAGE_LENGTH = 240;

const MAX_DTO_PAYLOAD_DEPTH = 64;
const MAX_DTO_PAYLOAD_OBJECTS = 20_000;
const MAX_DTO_PAYLOAD_KEYS = 100_000;

export class DtoValidationError extends Error {
    readonly issues: DtoValidationIssue[];
    readonly issuesTruncated: boolean;

    constructor(issues: DtoValidationIssue[], issuesTruncated = false) {
        // Keep request values out of controller responses and logs.
        super('Validation failed');
        this.name = 'DtoValidationError';
        this.issues = issues;
        this.issuesTruncated = issuesTruncated;
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

type PayloadInspection = 'safe' | 'forbiddenProperty' | 'tooComplex';

function inspectPayloadShape(value: unknown): PayloadInspection {
    if (typeof value !== 'object' || value === null) {
        return 'safe';
    }

    const pending: Array<{ value: object; depth: number }> = [
        { value, depth: 0 }
    ];
    const visited = new WeakSet<object>();
    let objectCount = 0;
    let keyCount = 0;

    while (pending.length > 0) {
        const current = pending.pop()!;
        if (visited.has(current.value)) {
            continue;
        }
        visited.add(current.value);
        objectCount += 1;
        if (
            objectCount > MAX_DTO_PAYLOAD_OBJECTS ||
            current.depth > MAX_DTO_PAYLOAD_DEPTH
        ) {
            return 'tooComplex';
        }

        for (const property in current.value) {
            if (!Object.prototype.hasOwnProperty.call(current.value, property)) {
                continue;
            }

            keyCount += 1;
            if (keyCount > MAX_DTO_PAYLOAD_KEYS) {
                return 'tooComplex';
            }
            if (FORBIDDEN_PROPERTY_NAMES.has(property)) {
                return 'forbiddenProperty';
            }

            // Inspect data properties without invoking an attacker-controlled getter.
            const descriptor = Object.getOwnPropertyDescriptor(
                current.value,
                property
            );
            if (!descriptor || !('value' in descriptor)) {
                continue;
            }

            const child = descriptor.value;
            if (typeof child === 'object' && child !== null) {
                if (pending.length >= MAX_DTO_PAYLOAD_OBJECTS) {
                    return 'tooComplex';
                }
                pending.push({ value: child, depth: current.depth + 1 });
            }
        }
    }

    return 'safe';
}

function boundedText(value: string, maximumLength: number): string {
    if (value.length <= maximumLength) {
        return value;
    }

    return `${value.slice(0, maximumLength - 1)}…`;
}

function issuePath(parent: string, property: string): string {
    const boundedProperty = boundedText(property, MAX_DTO_ISSUE_PATH_LENGTH);
    if (!parent) {
        return boundedProperty;
    }

    return boundedText(
        `${parent}.${boundedProperty}`,
        MAX_DTO_ISSUE_PATH_LENGTH
    );
}

function issueMessage(code: string, message: string): string {
    if (code === 'whitelistValidation') {
        return 'field is not allowed';
    }

    return boundedText(message, MAX_DTO_ISSUE_MESSAGE_LENGTH);
}

function toValidationIssues(errors: ValidationError[]): {
    issues: DtoValidationIssue[];
    issuesTruncated: boolean;
} {
    const issues: DtoValidationIssue[] = [];
    let issuesTruncated = false;
    const pending = errors
        .slice()
        .reverse()
        .map(error => ({ error, parent: '' }));

    while (pending.length > 0) {
        if (issues.length >= MAX_DTO_VALIDATION_ISSUES) {
            issuesTruncated = true;
            break;
        }

        const current = pending.pop()!;
        const property = issuePath(
            current.parent,
            String(current.error.property)
        );
        if (current.error.constraints) {
            const constraintCodes = Object.keys(current.error.constraints);
            issues.push({
                property: constraintCodes.includes('whitelistValidation')
                    ? current.parent || '$root'
                    : property,
                constraintCodes,
                constraints: constraintCodes.map(code =>
                    issueMessage(code, current.error.constraints![code])
                )
            });
        }

        const children = current.error.children ?? [];
        for (let index = children.length - 1; index >= 0; index -= 1) {
            pending.push({ error: children[index], parent: property });
        }
    }

    return { issues, issuesTruncated };
}

export async function validateDto<T extends object>(
    dtoClass: ClassConstructor<T>,
    plainObject: unknown
): Promise<T> {
    if (!isPlainObject(plainObject)) {
        throw new DtoValidationError([{
            property: '$root',
            constraintCodes: ['isPlainObject'],
            constraints: ['request body must be a plain object']
        }]);
    }

    const payloadInspection = inspectPayloadShape(plainObject);
    if (payloadInspection === 'forbiddenProperty') {
        throw new DtoValidationError([{
            property: '$root',
            constraintCodes: ['forbiddenPropertyName'],
            constraints: ['request body contains a forbidden property name']
        }]);
    }
    if (payloadInspection === 'tooComplex') {
        throw new DtoValidationError([{
            property: '$root',
            constraintCodes: ['payloadComplexity'],
            constraints: ['request body exceeds the structural complexity limit']
        }]);
    }

    const dto = plainToInstance(dtoClass, plainObject);

    const errors = await validate(dto, {
        whitelist: true,
        forbidNonWhitelisted: true,
        forbidUnknownValues: true,
        stopAtFirstError: true,
        validationError: {
            target: false,
            value: false
        }
    });

    if (errors.length > 0) {
        const result = toValidationIssues(errors);
        throw new DtoValidationError(result.issues, result.issuesTruncated);
    }

    return dto;
}

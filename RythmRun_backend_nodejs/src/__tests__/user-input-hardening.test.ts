import 'reflect-metadata';
import { jest } from '@jest/globals';

jest.unstable_mockModule('bcrypt', () => ({
    hash: jest.fn().mockResolvedValue('hashed-password'),
    compare: jest.fn()
}));

import { DtoValidationError, validateDto } from '../middleware/validation.middleware.js';
import { RegisterUserDto, UpdateProfileDto } from '../models/dto/user.dto.js';
const bcrypt = await import('bcrypt');
const { UserService } = await import('../services/user.service.js');

function createMockPrisma() {
    return {
        user: {
            findUnique: jest.fn(),
            create: jest.fn(),
            update: jest.fn()
        },
        refreshToken: {
            upsert: jest.fn(),
            deleteMany: jest.fn(),
            findFirst: jest.fn(),
            delete: jest.fn(),
            update: jest.fn()
        }
    };
}

const persistedUser = {
    id: 7,
    username: 'ada@example.com',
    password: 'hashed-password',
    firstname: 'Ada',
    lastname: 'Lovelace',
    profilePicturePath: null,
    profilePictureType: null,
    createdAt: new Date('2026-07-10T00:00:00.000Z'),
    updatedAt: new Date('2026-07-10T00:00:00.000Z')
};

describe('user DTO input hardening', () => {
    it('keeps valid registration and profile payloads working', async () => {
        const registration = await validateDto(RegisterUserDto, {
            username: 'ada@example.com',
            password: 'correct-horse-battery-staple',
            firstname: 'Ada',
            lastname: 'Lovelace'
        });
        const profile = await validateDto(UpdateProfileDto, {
            firstname: 'Augusta Ada',
            lastname: 'King'
        });

        expect(registration).toBeInstanceOf(RegisterUserDto);
        expect(registration).toMatchObject({
            username: 'ada@example.com',
            firstname: 'Ada',
            lastname: 'Lovelace'
        });
        expect(profile).toBeInstanceOf(UpdateProfileDto);
        expect(profile).toEqual({
            firstname: 'Augusta Ada',
            lastname: 'King'
        });
    });

    it.each([
        ['id', 999],
        ['profilePicturePath', '../../private/key'],
        ['profilePictureType', 'image/svg+xml'],
        ['createdAt', '2020-01-01T00:00:00.000Z'],
        ['role', 'admin'],
        ['refreshToken', 'attacker-selected-token']
    ])('rejects undeclared registration field %s', async (property, value) => {
        const payload = {
            username: 'ada@example.com',
            password: 'correct-horse-battery-staple',
            [property]: value
        };

        await expect(validateDto(RegisterUserDto, payload)).rejects.toBeInstanceOf(
            DtoValidationError
        );
    });

    it.each([
        ['id', 999],
        ['username', 'attacker@example.com'],
        ['password', 'attacker-selected-password'],
        ['profilePicturePath', '../../private/key'],
        ['profilePictureType', 'image/svg+xml'],
        ['updatedAt', '2020-01-01T00:00:00.000Z'],
        ['role', 'admin']
    ])('rejects undeclared profile field %s', async (property, value) => {
        const payload = {
            firstname: 'Ada',
            [property]: value
        };

        await expect(validateDto(UpdateProfileDto, payload)).rejects.toBeInstanceOf(
            DtoValidationError
        );
    });

    it('rejects nested unexpected objects', async () => {
        await expect(validateDto(UpdateProfileDto, {
            firstname: 'Ada',
            metadata: {
                profilePicturePath: '../../private/key'
            }
        })).rejects.toBeInstanceOf(DtoValidationError);
    });

    it('rejects prototype-like field names without polluting the object prototype', async () => {
        const payload = JSON.parse(
            '{"firstname":"Ada","__proto__":{"isAdmin":true}}'
        );

        await expect(validateDto(UpdateProfileDto, payload)).rejects.toMatchObject({
            name: 'DtoValidationError',
            message: 'Validation failed'
        });
        expect(({} as { isAdmin?: boolean }).isAdmin).toBeUndefined();
    });

    it('does not echo rejected request values in the validation error message', async () => {
        const sensitiveValue = 'do-not-return-this-input-value';

        await expect(validateDto(UpdateProfileDto, {
            firstname: 42,
            profilePicturePath: sensitiveValue
        })).rejects.not.toThrow(sensitiveValue);
    });

    it.each([null, [], 'firstname=Ada', 42])(
        'rejects non-object request body %p',
        async body => {
            await expect(validateDto(UpdateProfileDto, body)).rejects.toBeInstanceOf(
                DtoValidationError
            );
        }
    );
});

describe('UserService writable-field mapping', () => {
    const originalAccessSecret = process.env.JWT_SECRET;
    const originalRefreshSecret = process.env.REFRESH_TOKEN_SECRET;

    beforeAll(() => {
        process.env.JWT_SECRET = 'unit-test-access-secret-0123456789-abcdef';
        process.env.REFRESH_TOKEN_SECRET = 'unit-test-refresh-secret-0123456789-abcdef';
    });

    afterAll(() => {
        if (originalAccessSecret === undefined) {
            delete process.env.JWT_SECRET;
        } else {
            process.env.JWT_SECRET = originalAccessSecret;
        }

        if (originalRefreshSecret === undefined) {
            delete process.env.REFRESH_TOKEN_SECRET;
        } else {
            process.env.REFRESH_TOKEN_SECRET = originalRefreshSecret;
        }
    });

    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('maps only declared registration fields into Prisma data', async () => {
        const prisma = createMockPrisma();
        prisma.user.findUnique.mockResolvedValue(null);
        prisma.user.create.mockResolvedValue(persistedUser);
        const service = new UserService(prisma as any);
        const dto = Object.assign(new RegisterUserDto(), {
            username: 'ada@example.com',
            password: 'correct-horse-battery-staple',
            firstname: 'Ada',
            lastname: 'Lovelace',
            id: 999,
            profilePicturePath: '../../private/key',
            profilePictureType: 'image/svg+xml',
            role: 'admin'
        });

        const result = await service.register(dto);

        expect(bcrypt.hash).toHaveBeenCalledWith('correct-horse-battery-staple', 10);
        expect(prisma.user.create).toHaveBeenCalledWith({
            data: {
                username: 'ada@example.com',
                password: 'hashed-password',
                firstname: 'Ada',
                lastname: 'Lovelace'
            }
        });
        expect(prisma.user.create.mock.calls[0][0].data).not.toBe(dto);
        expect(result).toMatchObject({
            id: 7,
            username: 'ada@example.com',
            firstname: 'Ada',
            lastname: 'Lovelace',
            accessToken: expect.any(String),
            refreshToken: expect.any(String)
        });
    });

    it('maps only first and last name into Prisma profile updates', async () => {
        const prisma = createMockPrisma();
        prisma.user.findUnique.mockResolvedValue(persistedUser);
        prisma.user.update.mockResolvedValue({
            ...persistedUser,
            firstname: 'Augusta Ada',
            lastname: 'King'
        });
        const service = new UserService(prisma as any);
        const dto = Object.assign(new UpdateProfileDto(), {
            firstname: 'Augusta Ada',
            lastname: 'King',
            id: 999,
            username: 'attacker@example.com',
            password: 'attacker-selected-password',
            profilePicturePath: '../../private/key',
            profilePictureType: 'image/svg+xml',
            role: 'admin'
        });

        await service.updateProfile(7, dto);

        expect(prisma.user.update).toHaveBeenCalledWith({
            where: { id: 7 },
            data: {
                firstname: 'Augusta Ada',
                lastname: 'King'
            }
        });
        expect(prisma.user.update.mock.calls[0][0].data).not.toBe(dto);
    });
});

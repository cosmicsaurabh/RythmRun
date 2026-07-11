import 'reflect-metadata';

jest.mock('../services/s3.service', () => ({
  __esModule: true,
  default: {
    getActivityImageReadUrl: jest.fn((key: string) => ({
      url: `https://signed.example.com/${key}`,
      urlExpiresAt: '2026-06-09T10:15:00.000Z',
    })),
    deleteObject: jest.fn(async () => undefined),
  },
}));

import {
  ActivityDomainValidationError,
  ActivityNotFoundError,
  ActivityService,
} from '../services/activity.service';
import {
  CreateActivityDto,
  CURRENT_METRICS_VERSION,
  LEGACY_METRICS_VERSION,
  UpdateActivityDto,
} from '../models/dto/activity.dto';
import s3Service from '../services/s3.service';

// Keep root and transactional delegates distinct so a test fails if a write
// escapes the callback transaction.
function createMockPrisma() {
  const mockTx = {
    activity: {
      create: jest.fn(),
      findUnique: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    },
    location: {
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    statusChange: {
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
  };

  const prisma = {
    activity: {
      create: jest.fn(),
      findUnique: jest.fn(),
      findMany: jest.fn(),
      findFirst: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
      count: jest.fn(),
    },
    location: {
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    statusChange: {
      createMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    $transaction: jest.fn(async (fn: any) => fn(mockTx)),
  };

  return { prisma, mockTx };
}

describe('ActivityService', () => {
  let service: ActivityService;
  let prisma: any;
  let mockTx: any;

  const userId = 1;

  const baseActivityDto: CreateActivityDto = {
    clientSyncId: 'rr-00000001-0001-0001-abcd-1234567890ab',
    type: 'running',
    startTime: '2026-03-22T10:00:00.000Z',
    endTime: '2026-03-22T10:30:00.000Z',
    distance: 5000,
    duration: 1800,
    avgSpeed: 2.78,
    maxSpeed: 4.5,
    calories: 350,
    description: 'Morning run',
    isPublic: false,
    locations: [
      {
        latitude: 28.6139,
        longitude: 77.209,
        altitude: 216,
        timestamp: '2026-03-22T10:00:00.000Z',
        accuracy: 5,
        speed: 2.5,
      },
    ],
  };

  const fullActivityDto: CreateActivityDto = {
    ...baseActivityDto,
    duration: 1680,
    pausedDuration: 120,
    name: 'Morning Jog',
    elevationGain: 45.5,
    elevationLoss: 30.2,
    locations: [
      {
        latitude: 28.6139,
        longitude: 77.209,
        altitude: 216,
        timestamp: '2026-03-22T10:00:00.000Z',
        accuracy: 5,
        speed: 2.5,
        heading: 90.5,
      },
    ],
    statusChanges: [
      { status: 'active', timestamp: '2026-03-22T10:00:00.000Z' },
      { status: 'paused', timestamp: '2026-03-22T10:10:00.000Z' },
      { status: 'active', timestamp: '2026-03-22T10:12:00.000Z' },
      { status: 'completed', timestamp: '2026-03-22T10:30:00.000Z' },
    ],
  };

  const mockActivityReturn = {
    id: 1,
    userId: 1,
    clientSyncId: 'rr-00000001-0001-0001-abcd-1234567890ab',
    metricsVersion: LEGACY_METRICS_VERSION,
    type: 'running',
    startTime: new Date('2026-03-22T10:00:00.000Z'),
    endTime: new Date('2026-03-22T10:30:00.000Z'),
    distance: 5000,
    duration: 1680,
    avgSpeed: 2.78,
    maxSpeed: 4.5,
    calories: 350,
    description: 'Morning run',
    isPublic: false,
    pausedDuration: 120,
    name: 'Morning Jog',
    elevationGain: 45.5,
    elevationLoss: 30.2,
    locations: [
      {
        id: 1,
        activityId: 1,
        latitude: 28.6139,
        longitude: 77.209,
        altitude: 216,
        timestamp: new Date('2026-03-22T10:00:00.000Z'),
        accuracy: 5,
        speed: 2.5,
        heading: 90.5,
      },
    ],
    statusChanges: [
      { id: 1, activityId: 1, status: 'active', timestamp: new Date('2026-03-22T10:00:00.000Z') },
      { id: 2, activityId: 1, status: 'paused', timestamp: new Date('2026-03-22T10:10:00.000Z') },
      { id: 3, activityId: 1, status: 'active', timestamp: new Date('2026-03-22T10:12:00.000Z') },
      { id: 4, activityId: 1, status: 'completed', timestamp: new Date('2026-03-22T10:30:00.000Z') },
    ],
    images: [],
    _count: { comments: 0, likes: 0 },
  };

  beforeEach(() => {
    jest.clearAllMocks();
    const mocks = createMockPrisma();
    prisma = mocks.prisma;
    mockTx = mocks.mockTx;
    service = new ActivityService(prisma as any);
  });

  describe('createActivity', () => {
    it('should create activity with all new sync fields', async () => {
      mockTx.activity.findUnique.mockResolvedValueOnce(null);
      mockTx.activity.create.mockResolvedValue({ id: 1 });
      mockTx.location.createMany.mockResolvedValue({ count: 1 });
      mockTx.statusChange.createMany.mockResolvedValue({ count: 4 });
      mockTx.activity.findUnique.mockResolvedValue(mockActivityReturn);

      const result = await service.createActivity(userId, fullActivityDto);

      expect(mockTx.activity.findUnique).toHaveBeenNthCalledWith(1, {
        where: {
          userId_clientSyncId: {
            userId,
            clientSyncId: fullActivityDto.clientSyncId,
          },
        },
        include: expect.any(Object),
      });

      // Verify activity.create was called with new fields
      const createData = mockTx.activity.create.mock.calls[0][0].data;
      expect(createData.clientSyncId).toBe(fullActivityDto.clientSyncId);
      expect(createData.metricsVersion).toBe(LEGACY_METRICS_VERSION);
      expect(createData.pausedDuration).toBe(120);
      expect(createData.name).toBe('Morning Jog');
      expect(createData.elevationGain).toBe(45.5);
      expect(createData.elevationLoss).toBe(30.2);

      // Verify heading included in locations
      const locationData = mockTx.location.createMany.mock.calls[0][0].data;
      expect(locationData[0].heading).toBe(90.5);

      // Verify status changes were created
      expect(mockTx.statusChange.createMany).toHaveBeenCalledTimes(1);
      const scData = mockTx.statusChange.createMany.mock.calls[0][0].data;
      expect(scData).toHaveLength(4);
      expect(scData[0].status).toBe('active');
      expect(scData[1].status).toBe('paused');

      // Verify return includes statusChanges
      const findUniqueArgs = mockTx.activity.findUnique.mock.calls[0][0];
      expect(findUniqueArgs.include.statusChanges).toBe(true);

      expect(result).toEqual(mockActivityReturn);
    });

    it('should create activity without optional sync fields (backward compat)', async () => {
      mockTx.activity.findUnique.mockResolvedValueOnce(null);
      mockTx.activity.create.mockResolvedValue({ id: 2 });
      mockTx.location.createMany.mockResolvedValue({ count: 1 });
      mockTx.activity.findUnique.mockResolvedValue({
        ...mockActivityReturn,
        id: 2,
        pausedDuration: null,
        name: null,
        elevationGain: null,
        elevationLoss: null,
        statusChanges: [],
      });

      const result = await service.createActivity(userId, baseActivityDto);

      // Verify new fields are undefined (not sent)
      const createData = mockTx.activity.create.mock.calls[0][0].data;
      expect(createData.pausedDuration).toBeUndefined();
      expect(createData.name).toBeUndefined();
      expect(createData.elevationGain).toBeUndefined();
      expect(createData.elevationLoss).toBeUndefined();
      expect(createData.metricsVersion).toBe(LEGACY_METRICS_VERSION);

      // Verify heading is undefined in locations
      const locationData = mockTx.location.createMany.mock.calls[0][0].data;
      expect(locationData[0].heading).toBeUndefined();

      // Verify statusChange.createMany NOT called (no statusChanges in DTO)
      expect(mockTx.statusChange.createMany).not.toHaveBeenCalled();

      expect(result!.statusChanges).toEqual([]);
      expect(result!.metricsVersion).toBe(LEGACY_METRICS_VERSION);
    });

    it('should persist an explicit canonical metrics version for a new client', async () => {
      const dto: CreateActivityDto = {
        ...fullActivityDto,
        clientSyncId: 'rr-00000001-0001-0001-abcd-1234567890ac',
        metricsVersion: CURRENT_METRICS_VERSION,
        distance: 0,
        avgSpeed: 0,
        maxSpeed: 0,
      };
      const canonicalActivity = {
        ...mockActivityReturn,
        clientSyncId: dto.clientSyncId,
        metricsVersion: CURRENT_METRICS_VERSION,
      };

      mockTx.activity.findUnique.mockResolvedValueOnce(null);
      mockTx.activity.create.mockResolvedValue({ id: 2 });
      mockTx.location.createMany.mockResolvedValue({ count: 1 });
      mockTx.statusChange.createMany.mockResolvedValue({ count: 4 });
      mockTx.activity.findUnique.mockResolvedValue(canonicalActivity);

      const result = await service.createActivity(userId, dto);

      expect(mockTx.activity.create.mock.calls[0][0].data.metricsVersion).toBe(
        CURRENT_METRICS_VERSION,
      );
      expect(result!.metricsVersion).toBe(CURRENT_METRICS_VERSION);
    });

    it('should create activity with empty locations array', async () => {
      const dto: CreateActivityDto = {
        ...fullActivityDto,
        locations: [],
      };

      mockTx.activity.findUnique.mockResolvedValueOnce(null);
      mockTx.activity.create.mockResolvedValue({ id: 3 });
      mockTx.activity.findUnique.mockResolvedValue({ ...mockActivityReturn, id: 3, locations: [] });

      await service.createActivity(userId, dto);

      expect(mockTx.location.createMany).not.toHaveBeenCalled();
    });

    it('rejects a semantically invalid new activity before the first write', async () => {
      const dto: CreateActivityDto = {
        ...fullActivityDto,
        clientSyncId: 'rr-00000001-0001-0001-abcd-invalid-create',
        metricsVersion: CURRENT_METRICS_VERSION,
        avgSpeed: 5000 / 1680,
        locations: [
          {
            ...fullActivityDto.locations[0],
            accuracy: 50.001,
          },
        ],
      };
      mockTx.activity.findUnique.mockResolvedValue(null);

      await expect(service.createActivity(userId, dto)).rejects.toMatchObject({
        code: 'ACTIVITY_DOMAIN_INVALID',
        statusCode: 422,
        issues: expect.arrayContaining([
          expect.objectContaining({
            code: 'ACTIVITY_GPS_ACCURACY_INVALID',
            property: 'locations[0].accuracy',
          }),
        ]),
      });

      expect(mockTx.activity.create).not.toHaveBeenCalled();
      expect(mockTx.location.createMany).not.toHaveBeenCalled();
      expect(mockTx.statusChange.createMany).not.toHaveBeenCalled();
      expect(prisma.activity.create).not.toHaveBeenCalled();
    });

    it('keeps idempotent create retries ahead of semantic revalidation', async () => {
      mockTx.activity.findUnique.mockResolvedValue(mockActivityReturn);

      const result = await service.createActivity(userId, {
        ...fullActivityDto,
        endTime: fullActivityDto.startTime,
      });

      expect(result).toEqual(mockActivityReturn);
      expect(mockTx.activity.create).not.toHaveBeenCalled();
    });

    it('throws inside the transaction when the created row cannot be reloaded', async () => {
      mockTx.activity.findUnique.mockResolvedValueOnce(null);
      mockTx.activity.create.mockResolvedValue({ id: 77 });
      mockTx.location.createMany.mockResolvedValue({ count: 1 });
      mockTx.statusChange.createMany.mockResolvedValue({ count: 4 });
      mockTx.activity.findUnique.mockResolvedValueOnce(null);

      await expect(
        service.createActivity(userId, fullActivityDto),
      ).rejects.toThrow('Created activity could not be reloaded');

      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(mockTx.activity.create).toHaveBeenCalledTimes(1);
      expect(prisma.activity.create).not.toHaveBeenCalled();
    });

    it('should preserve the existing metric version when clientSyncId already exists', async () => {
      mockTx.activity.findUnique.mockResolvedValue(mockActivityReturn);

      const result = await service.createActivity(userId, {
        ...fullActivityDto,
        metricsVersion: CURRENT_METRICS_VERSION,
      });

      expect(mockTx.activity.create).not.toHaveBeenCalled();
      expect(mockTx.location.createMany).not.toHaveBeenCalled();
      expect(mockTx.statusChange.createMany).not.toHaveBeenCalled();
      expect(result).toEqual(mockActivityReturn);
      expect(result!.metricsVersion).toBe(LEGACY_METRICS_VERSION);
    });
  });

  describe('getActivities', () => {
    it('should include statusChanges in results', async () => {
      prisma.activity.findMany.mockResolvedValue([mockActivityReturn]);
      prisma.activity.count.mockResolvedValue(1);

      const result = await service.getActivities(userId, { page: 1, limit: 10 });

      // Check that findMany includes statusChanges
      const findManyArgs = prisma.activity.findMany.mock.calls[0][0];
      expect(findManyArgs.include.statusChanges).toBe(true);
      expect(findManyArgs.include.locations).toBe(true);
      expect(findManyArgs.include.images).toEqual({
        where: {
          status: 'UPLOADED',
          deletedAt: null,
        },
        orderBy: {
          sortOrder: 'asc',
        },
      });

      expect(result.activities).toHaveLength(1);
      expect(result.activities[0].statusChanges).toHaveLength(4);
      expect(result.activities[0].metricsVersion).toBe(LEGACY_METRICS_VERSION);
      expect(result.pagination.total).toBe(1);
    });

    it('should add signed image URLs to results', async () => {
      const activityWithImage = {
        ...mockActivityReturn,
        images: [
          {
            id: 10,
            activityId: 1,
            userId: 1,
            clientImageId: 'img_client_123456',
            s3Key: 'activity-images/1/1/img_client_123456.jpg',
            contentType: 'image/jpeg',
            sizeBytes: 1024,
            checksumSha256: null,
            width: 800,
            height: 600,
            sortOrder: 0,
            caption: 'Finish line',
            status: 'UPLOADED',
            uploadedAt: new Date('2026-06-09T10:00:00.000Z'),
            deletedAt: null,
            createdAt: new Date('2026-06-09T10:00:00.000Z'),
            updatedAt: new Date('2026-06-09T10:00:00.000Z'),
          },
        ],
      };

      prisma.activity.findMany.mockResolvedValue([activityWithImage]);
      prisma.activity.count.mockResolvedValue(1);

      const result = await service.getActivities(userId, { page: 1, limit: 10 });
      const image = result.activities[0].images[0] as any;

      expect(s3Service.getActivityImageReadUrl).toHaveBeenCalledWith(
        'activity-images/1/1/img_client_123456.jpg',
      );
      expect(image.url).toBe(
        'https://signed.example.com/activity-images/1/1/img_client_123456.jpg',
      );
      expect(image.urlExpiresAt).toBe('2026-06-09T10:15:00.000Z');
      expect(image.s3Key).toBeUndefined();
    });
  });

  describe('getActivityById', () => {
    it('should include statusChanges in result', async () => {
      prisma.activity.findFirst.mockResolvedValue(mockActivityReturn);

      const result = await service.getActivityById(userId, 1);

      const findFirstArgs = prisma.activity.findFirst.mock.calls[0][0];
      expect(findFirstArgs.include.statusChanges).toBe(true);
      expect(findFirstArgs.include.locations).toBe(true);
      expect(findFirstArgs.include.images.where).toEqual({
        status: 'UPLOADED',
        deletedAt: null,
      });

      expect(result.statusChanges).toHaveLength(4);
      expect(result.pausedDuration).toBe(120);
      expect(result.name).toBe('Morning Jog');
      expect(result.elevationGain).toBe(45.5);
      expect(result.elevationLoss).toBe(30.2);
      expect(result.metricsVersion).toBe(LEGACY_METRICS_VERSION);
    });
  });

  describe('updateActivity', () => {
    const updateDto: UpdateActivityDto = {
      name: 'Evening Run',
      pausedDuration: 60,
      duration: 1740,
      elevationGain: 50,
      elevationLoss: 35,
      locations: [
        {
          latitude: 28.614,
          longitude: 77.21,
          altitude: 220,
          timestamp: '2026-03-22T10:01:00.000Z',
          accuracy: 3,
          speed: 3.0,
          heading: 180,
        },
      ],
      statusChanges: [
        { status: 'active', timestamp: '2026-03-22T10:00:00.000Z' },
        { status: 'paused', timestamp: '2026-03-22T10:10:00.000Z' },
        { status: 'active', timestamp: '2026-03-22T10:11:00.000Z' },
        { status: 'completed', timestamp: '2026-03-22T10:30:00.000Z' },
      ],
    };

    function arrangeOwnedUpdate(
      result: Record<string, unknown> = mockActivityReturn,
      existing: Record<string, unknown> = mockActivityReturn,
    ) {
      mockTx.activity.findFirst.mockResolvedValue(existing);
      mockTx.activity.update.mockResolvedValue(result);
    }

    it('replaces both non-empty collections in one owner-scoped nested update', async () => {
      arrangeOwnedUpdate({
        ...mockActivityReturn,
        name: 'Evening Run',
        pausedDuration: 60,
        duration: 1740,
        elevationGain: 50,
        elevationLoss: 35,
        statusChanges: [
          { id: 5, activityId: 1, status: 'active', timestamp: new Date('2026-03-22T10:00:00.000Z') },
          { id: 6, activityId: 1, status: 'paused', timestamp: new Date('2026-03-22T10:10:00.000Z') },
          { id: 7, activityId: 1, status: 'active', timestamp: new Date('2026-03-22T10:11:00.000Z') },
          { id: 8, activityId: 1, status: 'completed', timestamp: new Date('2026-03-22T10:30:00.000Z') },
        ],
      });

      const result = await service.updateActivity(userId, 1, updateDto);

      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      expect(mockTx.activity.findFirst).toHaveBeenCalledWith({
        where: { id: 1, userId },
        include: {
          locations: false,
          statusChanges: false,
        },
      });

      const updateArgs = mockTx.activity.update.mock.calls[0][0];
      const updateData = mockTx.activity.update.mock.calls[0][0].data;
      expect(updateArgs.where).toEqual({ id: 1, userId });
      expect(updateArgs.include.statusChanges).toBe(true);
      expect(updateData.name).toBe('Evening Run');
      expect(updateData.pausedDuration).toBe(60);
      expect(updateData.duration).toBe(1740);
      expect(updateData.elevationGain).toBe(50);
      expect(updateData.elevationLoss).toBe(35);
      expect(updateData).not.toHaveProperty('metricsVersion');

      expect(updateData.locations.deleteMany).toEqual({});
      const locationData = updateData.locations.createMany.data;
      expect(locationData[0].heading).toBe(180);
      expect(locationData[0]).not.toHaveProperty('activityId');

      expect(updateData.statusChanges.deleteMany).toEqual({});
      const scData = updateData.statusChanges.createMany.data;
      expect(scData).toHaveLength(4);
      expect(scData[0]).not.toHaveProperty('activityId');

      expect(mockTx.location.deleteMany).not.toHaveBeenCalled();
      expect(mockTx.location.createMany).not.toHaveBeenCalled();
      expect(mockTx.statusChange.deleteMany).not.toHaveBeenCalled();
      expect(mockTx.statusChange.createMany).not.toHaveBeenCalled();
      expect(prisma.activity.findFirst).not.toHaveBeenCalled();
      expect(prisma.activity.update).not.toHaveBeenCalled();

      expect(result!.name).toBe('Evening Run');
    });

    it('preserves both collections when a name-only patch omits them', async () => {
      arrangeOwnedUpdate({
        ...mockActivityReturn,
        name: 'Renamed legacy workout',
      }, {
        ...mockActivityReturn,
        duration: 1800,
        locations: [
          {
            ...mockActivityReturn.locations[0],
            timestamp: new Date('2026-03-22T09:00:00.000Z'),
          },
        ],
        statusChanges: [...mockActivityReturn.statusChanges].reverse(),
      });

      await service.updateActivity(userId, 1, {
        name: 'Renamed legacy workout',
      });

      const updateData = mockTx.activity.update.mock.calls[0][0].data;
      expect(updateData).not.toHaveProperty('locations');
      expect(updateData).not.toHaveProperty('statusChanges');
      // The persisted legacy fixture has inconsistent timing and dirty child
      // history. An unrelated metadata patch must remain compatible.
      expect(updateData).toEqual({ name: 'Renamed legacy workout' });
    });

    it.each([
      [
        'locations',
        { locations: [] },
        'locations',
        'statusChanges',
      ],
      [
        'status changes',
        { statusChanges: [] },
        'statusChanges',
        'locations',
      ],
    ])(
      'clears only explicitly empty %s',
      async (_label, patch, clearedProperty, preservedProperty) => {
        arrangeOwnedUpdate(mockActivityReturn);

        await service.updateActivity(userId, 1, patch as UpdateActivityDto);

        const updateData = mockTx.activity.update.mock.calls[0][0].data;
        expect(updateData[clearedProperty]).toEqual({ deleteMany: {} });
        expect(updateData).not.toHaveProperty(preservedProperty);
      },
    );

    it('clears both collections when both explicit arrays are empty', async () => {
      arrangeOwnedUpdate(mockActivityReturn);

      await service.updateActivity(userId, 1, {
        locations: [],
        statusChanges: [],
      });

      const updateData = mockTx.activity.update.mock.calls[0][0].data;
      expect(updateData.locations).toEqual({ deleteMany: {} });
      expect(updateData.statusChanges).toEqual({ deleteMany: {} });
    });

    it('clears canonical status history without changing pause aggregates', async () => {
      arrangeOwnedUpdate(mockActivityReturn, {
        ...mockActivityReturn,
        metricsVersion: CURRENT_METRICS_VERSION,
        distance: 0,
        avgSpeed: 0,
        maxSpeed: 0,
      });

      await service.updateActivity(userId, 1, { statusChanges: [] });

      expect(mockTx.activity.update.mock.calls[0][0].data.statusChanges).toEqual({
        deleteMany: {},
      });
      expect(mockTx.activity.update.mock.calls[0][0].data).not.toHaveProperty(
        'pausedDuration',
      );
      expect(mockTx.activity.findFirst.mock.calls[0][0].include.statusChanges)
        .toEqual(expect.objectContaining({ select: expect.any(Object) }));
    });

    it('validates merged timeline state before any write', async () => {
      arrangeOwnedUpdate(mockActivityReturn);

      const promise = service.updateActivity(userId, 1, { duration: 1600 });

      await expect(promise).rejects.toMatchObject({
        code: 'ACTIVITY_DOMAIN_INVALID',
        statusCode: 422,
        issues: expect.arrayContaining([
          expect.objectContaining({
            code: 'ACTIVITY_DURATION_INVALID',
            property: 'duration',
          }),
        ]),
      });
      await expect(promise).rejects.toBeInstanceOf(
        ActivityDomainValidationError,
      );
      expect(mockTx.activity.update).not.toHaveBeenCalled();
      expect(prisma.activity.update).not.toHaveBeenCalled();
    });

    it('loads omitted collections when a window change must revalidate them', async () => {
      arrangeOwnedUpdate(mockActivityReturn);

      await expect(
        service.updateActivity(userId, 1, {
          startTime: '2026-03-22T10:02:00.000Z',
          duration: 1560,
        }),
      ).rejects.toMatchObject({
        issues: expect.arrayContaining([
          expect.objectContaining({
            code: 'ACTIVITY_TIMESTAMP_OUTSIDE_WINDOW',
            property: 'locations[0].timestamp',
          }),
          expect.objectContaining({
            code: 'ACTIVITY_TIMESTAMP_OUTSIDE_WINDOW',
            property: 'statusChanges[0].timestamp',
          }),
        ]),
      });

      expect(mockTx.activity.findFirst).toHaveBeenCalledWith({
        where: { id: 1, userId },
        include: {
          locations: {
            select: {
              latitude: true,
              longitude: true,
              accuracy: true,
              speed: true,
              timestamp: true,
            },
            orderBy: { id: 'asc' },
          },
          statusChanges: {
            select: {
              status: true,
              timestamp: true,
            },
            orderBy: { id: 'asc' },
          },
        },
      });
      expect(mockTx.activity.update).not.toHaveBeenCalled();
    });

    it('leaves all replacement work in the rejected atomic Prisma update', async () => {
      const nestedWriteFailure = new Error('nested create failed');
      let committedCollections = {
        locations: ['old-location'],
        statusChanges: ['old-status'],
      };
      mockTx.activity.findFirst.mockResolvedValue(mockActivityReturn);
      prisma.$transaction.mockImplementationOnce(async (callback: any) => {
        const transactionSnapshot = {
          locations: [...committedCollections.locations],
          statusChanges: [...committedCollections.statusChanges],
        };
        mockTx.activity.update.mockImplementationOnce(async (args: any) => {
          if (args.data.locations) {
            transactionSnapshot.locations = ['new-location'];
          }
          if (args.data.statusChanges) {
            transactionSnapshot.statusChanges = ['new-status'];
          }
          throw nestedWriteFailure;
        });

        const result = await callback(mockTx);
        committedCollections = transactionSnapshot;
        return result;
      });

      await expect(
        service.updateActivity(userId, 1, updateDto),
      ).rejects.toBe(nestedWriteFailure);

      expect(mockTx.activity.update).toHaveBeenCalledTimes(1);
      const updateData = mockTx.activity.update.mock.calls[0][0].data;
      expect(updateData.locations).toMatchObject({ deleteMany: {} });
      expect(updateData.statusChanges).toMatchObject({ deleteMany: {} });
      expect(mockTx.location.deleteMany).not.toHaveBeenCalled();
      expect(mockTx.statusChange.deleteMany).not.toHaveBeenCalled();
      expect(prisma.activity.update).not.toHaveBeenCalled();
      expect(committedCollections).toEqual({
        locations: ['old-location'],
        statusChanges: ['old-status'],
      });
    });

    it('throws a typed not-found error before writes for another owner', async () => {
      mockTx.activity.findFirst.mockResolvedValue(null);

      const promise = service.updateActivity(userId, 999, updateDto);

      await expect(promise).rejects.toBeInstanceOf(ActivityNotFoundError);
      await expect(promise).rejects.toMatchObject({
        code: 'ACTIVITY_NOT_FOUND',
        statusCode: 404,
        message: 'Activity not found or unauthorized',
      });
      expect(mockTx.activity.update).not.toHaveBeenCalled();
      expect(prisma.activity.findFirst).not.toHaveBeenCalled();
    });

    it('maps an owner-scoped update race from Prisma P2025 to not found', async () => {
      mockTx.activity.findFirst.mockResolvedValue(mockActivityReturn);
      mockTx.activity.update.mockRejectedValue({ code: 'P2025' });

      await expect(
        service.updateActivity(userId, 1, { name: 'Race-safe name' }),
      ).rejects.toBeInstanceOf(ActivityNotFoundError);
    });

    it('retries a serializable PATCH conflict and revalidates the merged state', async () => {
      arrangeOwnedUpdate({
        ...mockActivityReturn,
        name: 'Serializable retry',
      });
      let attempt = 0;
      prisma.$transaction.mockImplementation(
        async (callback: any, options: Record<string, unknown>) => {
          expect(options).toEqual({ isolationLevel: 'Serializable' });
          const result = await callback(mockTx);
          attempt += 1;
          if (attempt === 1) {
            throw { code: 'P2034' };
          }
          return result;
        },
      );

      await service.updateActivity(userId, 1, {
        name: 'Serializable retry',
      });

      expect(prisma.$transaction).toHaveBeenCalledTimes(2);
      expect(mockTx.activity.findFirst).toHaveBeenCalledTimes(2);
      expect(mockTx.activity.update).toHaveBeenCalledTimes(2);
    });
  });

  describe('deleteActivity', () => {
    it('should delete known activity image objects before deleting the activity', async () => {
      const firstKey = 'activity-images/1/1/img_client_123456.jpg';
      const secondKey = 'activity-images/1/1/img_client_abcdef.jpg';
      prisma.activity.findFirst.mockResolvedValue({
        ...mockActivityReturn,
        images: [
          { s3Key: firstKey },
          { s3Key: secondKey },
          { s3Key: firstKey },
        ],
      });
      prisma.activity.delete.mockResolvedValue({ id: 1 });

      const result = await service.deleteActivity(userId, 1);

      expect(prisma.activity.findFirst).toHaveBeenCalledWith({
        where: {
          id: 1,
          userId,
        },
        include: {
          images: {
            select: {
              s3Key: true,
            },
          },
        },
      });
      expect(s3Service.deleteObject).toHaveBeenCalledTimes(2);
      expect(s3Service.deleteObject).toHaveBeenNthCalledWith(1, firstKey);
      expect(s3Service.deleteObject).toHaveBeenNthCalledWith(2, secondKey);
      expect(prisma.activity.delete).toHaveBeenCalledWith({
        where: { id: 1 },
      });
      expect(
        (s3Service.deleteObject as jest.Mock).mock.invocationCallOrder[0],
      ).toBeLessThan(prisma.activity.delete.mock.invocationCallOrder[0]);
      expect(result).toEqual({ message: 'Activity deleted successfully' });
    });

    it('should not delete the activity row if image object cleanup fails', async () => {
      prisma.activity.findFirst.mockResolvedValue({
        ...mockActivityReturn,
        images: [{ s3Key: 'activity-images/1/1/img_client_123456.jpg' }],
      });
      (s3Service.deleteObject as jest.Mock).mockRejectedValueOnce(
        new Error('S3 unavailable'),
      );

      await expect(service.deleteActivity(userId, 1)).rejects.toThrow(
        'S3 unavailable',
      );

      expect(prisma.activity.delete).not.toHaveBeenCalled();
    });

    it('should reject deleting another user activity without S3 cleanup', async () => {
      prisma.activity.findFirst.mockResolvedValue(null);

      await expect(service.deleteActivity(userId, 999)).rejects.toThrow(
        'Activity not found or unauthorized',
      );

      expect(s3Service.deleteObject).not.toHaveBeenCalled();
      expect(prisma.activity.delete).not.toHaveBeenCalled();
    });
  });
});

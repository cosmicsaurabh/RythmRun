import 'reflect-metadata';

jest.mock('../services/s3.service', () => ({
  __esModule: true,
  default: {
    getActivityImageReadUrl: jest.fn((key: string) => ({
      url: `https://signed.example.com/${key}`,
      urlExpiresAt: '2026-06-09T10:15:00.000Z',
    })),
  },
}));

import { ActivityService } from '../services/activity.service';
import { CreateActivityDto, UpdateActivityDto } from '../models/dto/activity.dto';
import s3Service from '../services/s3.service';

// Mock Prisma transaction helper
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
    ...mockTx,
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
    type: 'running',
    startTime: new Date('2026-03-22T10:00:00.000Z'),
    endTime: new Date('2026-03-22T10:30:00.000Z'),
    distance: 5000,
    duration: 1800,
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

      // Verify heading is undefined in locations
      const locationData = mockTx.location.createMany.mock.calls[0][0].data;
      expect(locationData[0].heading).toBeUndefined();

      // Verify statusChange.createMany NOT called (no statusChanges in DTO)
      expect(mockTx.statusChange.createMany).not.toHaveBeenCalled();

      expect(result!.statusChanges).toEqual([]);
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

    it('should return the existing activity when clientSyncId already exists', async () => {
      mockTx.activity.findUnique.mockResolvedValue(mockActivityReturn);

      const result = await service.createActivity(userId, fullActivityDto);

      expect(mockTx.activity.create).not.toHaveBeenCalled();
      expect(mockTx.location.createMany).not.toHaveBeenCalled();
      expect(mockTx.statusChange.createMany).not.toHaveBeenCalled();
      expect(result).toEqual(mockActivityReturn);
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
    });
  });

  describe('updateActivity', () => {
    const updateDto: UpdateActivityDto = {
      name: 'Evening Run',
      pausedDuration: 60,
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
        { status: 'completed', timestamp: '2026-03-22T10:30:00.000Z' },
      ],
    };

    it('should update activity with new sync fields', async () => {
      prisma.activity.findFirst.mockResolvedValue({ id: 1, userId: 1 });
      mockTx.activity.update.mockResolvedValue({ id: 1 });
      mockTx.location.deleteMany.mockResolvedValue({ count: 1 });
      mockTx.location.createMany.mockResolvedValue({ count: 1 });
      mockTx.statusChange.deleteMany.mockResolvedValue({ count: 4 });
      mockTx.statusChange.createMany.mockResolvedValue({ count: 2 });
      mockTx.activity.findUnique.mockResolvedValue({
        ...mockActivityReturn,
        name: 'Evening Run',
        pausedDuration: 60,
        elevationGain: 50,
        elevationLoss: 35,
        statusChanges: [
          { id: 5, activityId: 1, status: 'active', timestamp: new Date('2026-03-22T10:00:00.000Z') },
          { id: 6, activityId: 1, status: 'completed', timestamp: new Date('2026-03-22T10:30:00.000Z') },
        ],
      });

      const result = await service.updateActivity(userId, 1, updateDto);

      // Verify update includes new fields
      const updateData = mockTx.activity.update.mock.calls[0][0].data;
      expect(updateData.name).toBe('Evening Run');
      expect(updateData.pausedDuration).toBe(60);
      expect(updateData.elevationGain).toBe(50);
      expect(updateData.elevationLoss).toBe(35);

      // Verify heading in location recreation
      const locationData = mockTx.location.createMany.mock.calls[0][0].data;
      expect(locationData[0].heading).toBe(180);

      // Verify old status changes deleted, new ones created
      expect(mockTx.statusChange.deleteMany).toHaveBeenCalledWith({ where: { activityId: 1 } });
      expect(mockTx.statusChange.createMany).toHaveBeenCalledTimes(1);
      const scData = mockTx.statusChange.createMany.mock.calls[0][0].data;
      expect(scData).toHaveLength(2);

      // Verify return includes statusChanges
      const findUniqueArgs = mockTx.activity.findUnique.mock.calls[0][0];
      expect(findUniqueArgs.include.statusChanges).toBe(true);

      expect(result!.name).toBe('Evening Run');
    });

    it('should delete old status changes even if no new ones provided', async () => {
      prisma.activity.findFirst.mockResolvedValue({ id: 1, userId: 1 });
      mockTx.activity.update.mockResolvedValue({ id: 1 });
      mockTx.statusChange.deleteMany.mockResolvedValue({ count: 4 });
      mockTx.activity.findUnique.mockResolvedValue({
        ...mockActivityReturn,
        statusChanges: [],
      });

      await service.updateActivity(userId, 1, { description: 'updated' });

      // statusChange.deleteMany should always be called
      expect(mockTx.statusChange.deleteMany).toHaveBeenCalledWith({ where: { activityId: 1 } });
      // But createMany should NOT be called (no new statusChanges)
      expect(mockTx.statusChange.createMany).not.toHaveBeenCalled();
    });

    it('should throw if activity not found', async () => {
      prisma.activity.findFirst.mockResolvedValue(null);

      await expect(service.updateActivity(userId, 999, updateDto))
        .rejects.toThrow('Activity not found or unauthorized');
    });
  });
});

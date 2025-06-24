import { PrismaClient } from '../../generated/prisma';
import * as bcrypt from 'bcrypt';

const prisma = new PrismaClient();

async function main() {
  // Clean up existing data
  await prisma.like.deleteMany();
  await prisma.comment.deleteMany();
  await prisma.location.deleteMany();
  await prisma.activity.deleteMany();
  await prisma.refreshToken.deleteMany();
  await prisma.friend.deleteMany();
  await prisma.user.deleteMany();

  // Create users
  const user1 = await prisma.user.create({
    data: {
      username: 'john_runner',
      password: await bcrypt.hash('password123', 10),
      firstname: 'John',
      lastname: 'Doe'
    }
  });

  const user2 = await prisma.user.create({
    data: {
      username: 'sarah_fitness',
      password: await bcrypt.hash('password123', 10),
      firstname: 'Sarah',
      lastname: 'Smith'
    }
  });

  // Create activities
  const activity1 = await prisma.activity.create({
    data: {
      userId: user1.id,
      type: 'RUN',
      startTime: new Date('2024-03-24T08:00:00Z'),
      endTime: new Date('2024-03-24T09:00:00Z'),
      distance: 5000, // 5km
      duration: 3600, // 1 hour in seconds
      avgSpeed: 1.39, // 5km/h
      maxSpeed: 2.78, // 10km/h
      calories: 500,
      description: 'Morning run in the park',
      isPublic: true,
      locations: {
        create: [
          {
            latitude: 37.7749,
            longitude: -122.4194,
            altitude: 0,
            timestamp: new Date('2024-03-24T08:00:00Z'),
            accuracy: 10,
            speed: 1.39
          },
          {
            latitude: 37.7750,
            longitude: -122.4195,
            altitude: 5,
            timestamp: new Date('2024-03-24T08:30:00Z'),
            accuracy: 10,
            speed: 2.78
          }
        ]
      }
    }
  });

  // Create friendship
  await prisma.friend.create({
    data: {
      user1Id: user1.id,
      user2Id: user2.id,
      status: 'ACCEPTED'
    }
  });

  // Create comment
  await prisma.comment.create({
    data: {
      activityId: activity1.id,
      userId: user2.id,
      content: 'Great pace! 💪'
    }
  });

  // Create like
  await prisma.like.create({
    data: {
      activityId: activity1.id,
      userId: user2.id
    }
  });

  console.log('Test data created successfully!');
  console.log('Users created:', { user1: user1.username, user2: user2.username });
  console.log('Activity created for:', user1.username);
  console.log('Comment and like added by:', user2.username);
}

main()
  .catch((e) => {
    console.error('Error seeding data:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  }); 
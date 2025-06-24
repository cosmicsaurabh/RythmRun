# RythmRun Node.js Backend - Resume Project Requirements

## 1. Project Overview

### Purpose
Rebuild the Spring Boot RythmRun backend using modern Node.js to showcase full-stack development skills. Perfect resume project demonstrating REST API development, database design, authentication, real-time features, and modern backend practices.

### Tech Stack (Resume Highlights)
- **Node.js + TypeScript** - Modern backend development
- **Express.js** - RESTful API framework
- **PostgreSQL + Prisma** - Database and modern ORM
- **JWT Authentication** - Secure user sessions
- **Bcrypt** - Password security
- **Multer** - File upload handling
- **Jest + Supertest** - Comprehensive testing
- **Docker** - Containerization
- **Swagger** - API documentation

## 2. Core Features (Resume Skills)

### 🔐 Authentication & Security
- **JWT-based authentication** with refresh tokens
- **Password hashing** with bcrypt
- **Protected routes** middleware
- **Email verification** and password reset
- **Input validation** and sanitization

### 🏃 Activity Management
- **CRUD operations** for fitness activities
- **GPS data handling** (location tracking)
- **File uploads** for profile pictures
- **Activity calculations** (distance, speed, time)
- **Pagination** and filtering

### 👥 Social Features
- **Friend request system** (pending, accepted, rejected)
- **Activity feed** with friends' activities
- **Like/comment system** on activities
- **User search** functionality

### 📊 Data & API Design
- **RESTful API design** with proper HTTP methods
- **Database relationships** and constraints
- **Error handling** with proper status codes
- **Request/response validation**
- **API documentation** with Swagger

## 3. Project Structure (Clean Architecture)

```
src/
├── controllers/           # HTTP request handlers
│   ├── authController.js
│   ├── userController.js
│   ├── activityController.js
│   └── friendController.js
├── services/             # Business logic
│   ├── authService.js
│   ├── userService.js
│   ├── activityService.js
│   └── friendService.js
├── repositories/         # Data access layer
│   ├── userRepository.js
│   └── activityRepository.js
├── models/              # Database models (Prisma)
│   └── schema.prisma
├── middleware/          # Express middleware
│   ├── auth.js
│   ├── validation.js
│   └── errorHandler.js
├── routes/             # API routes
│   ├── auth.js
│   ├── users.js
│   └── activities.js
├── utils/              # Helper functions
│   ├── jwt.js
│   ├── bcrypt.js
│   └── validation.js
├── config/             # Configuration
│   ├── database.js
│   └── swagger.js
└── app.js              # Express app setup
```

## 4. Database Schema (Core Tables)

### Prisma Schema (schema.prisma)
```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id                    String    @id @default(cuid())
  firstname             String?
  lastname              String?
  username              String    @unique
  password              String
  profilePicture        Bytes?
  profilePictureType    String?
  createdAt             DateTime  @default(now())
  
  // Relations
  activities            Activity[]
  sentFriendRequests    FriendRequest[] @relation("Requester")
  receivedFriendRequests FriendRequest[] @relation("Receiver")
  activityComments      ActivityComment[]
  activityLikes         ActivityLike[]
  
  @@map("users")
}

model Activity {
  id            String        @id @default(cuid())
  type          ActivityType
  startDatetime DateTime
  endDatetime   DateTime
  distance      Float
  speed         Float
  time          BigInt
  userId        String
  createdAt     DateTime      @default(now())
  
  // Relations
  user          User          @relation(fields: [userId], references: [id], onDelete: Cascade)
  locations     Location[]
  comments      ActivityComment[]
  likes         ActivityLike[]
  
  @@map("activities")
}

model Location {
  id         String   @id @default(cuid())
  latitude   Float
  longitude  Float
  activityId String
  timestamp  DateTime @default(now())
  
  activity   Activity @relation(fields: [activityId], references: [id], onDelete: Cascade)
  
  @@map("locations")
}

model FriendRequest {
  id          String              @id @default(cuid())
  requesterId String
  receiverId  String
  status      FriendRequestStatus @default(PENDING)
  createdAt   DateTime            @default(now())
  updatedAt   DateTime            @updatedAt
  
  requester   User @relation("Requester", fields: [requesterId], references: [id], onDelete: Cascade)
  receiver    User @relation("Receiver", fields: [receiverId], references: [id], onDelete: Cascade)
  
  @@unique([requesterId, receiverId])
  @@map("friend_requests")
}

enum ActivityType {
  RUNNING
  WALKING
  CYCLING
}

enum FriendRequestStatus {
  PENDING
  ACCEPTED
  REJECTED
}
```

## 5. Essential Dependencies (package.json)

```json
{
  "name": "rythmrun-backend",
  "version": "1.0.0",
  "scripts": {
    "dev": "nodemon src/app.js",
    "start": "node src/app.js",
    "test": "jest",
    "prisma:generate": "prisma generate",
    "prisma:migrate": "prisma migrate dev",
    "build": "tsc"
  },
  "dependencies": {
    "express": "^4.18.2",
    "prisma": "^5.0.0",
    "@prisma/client": "^5.0.0",
    "bcryptjs": "^2.4.3",
    "jsonwebtoken": "^9.0.2",
    "multer": "^1.4.5",
    "cors": "^2.8.5",
    "helmet": "^7.0.0",
    "express-rate-limit": "^6.10.0",
    "joi": "^17.9.2",
    "dotenv": "^16.3.1",
    "nodemailer": "^6.9.4",
    "swagger-ui-express": "^5.0.0",
    "swagger-jsdoc": "^6.2.8"
  },
  "devDependencies": {
    "nodemon": "^3.0.1",
    "jest": "^29.6.2",
    "supertest": "^6.3.3",
    "@types/node": "^20.4.8",
    "typescript": "^5.1.6"
  }
}
```

## 6. Key Implementation Examples

### Authentication Middleware
```javascript
const jwt = require('jsonwebtoken');
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

const authenticateToken = async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await prisma.user.findUnique({
      where: { id: decoded.userId }
    });
    
    if (!user) {
      return res.status(401).json({ error: 'Invalid token' });
    }
    
    req.user = user;
    next();
  } catch (error) {
    return res.status(403).json({ error: 'Invalid token' });
  }
};

module.exports = { authenticateToken };
```

### Activity Controller
```javascript
const activityService = require('../services/activityService');
const { validateActivity } = require('../utils/validation');

class ActivityController {
  async createActivity(req, res) {
    try {
      const { error } = validateActivity(req.body);
      if (error) {
        return res.status(400).json({ error: error.details[0].message });
      }

      const activity = await activityService.createActivity({
        ...req.body,
        userId: req.user.id
      });

      res.status(201).json(activity);
    } catch (error) {
      res.status(500).json({ error: 'Failed to create activity' });
    }
  }

  async getActivities(req, res) {
    try {
      const { page = 0, size = 20 } = req.query;
      const activities = await activityService.getUserActivities(
        req.user.id, 
        parseInt(page), 
        parseInt(size)
      );
      res.json(activities);
    } catch (error) {
      res.status(500).json({ error: 'Failed to fetch activities' });
    }
  }

  async getFriendsActivities(req, res) {
    try {
      const { page = 0, size = 10 } = req.query;
      const activities = await activityService.getFriendsActivities(
        req.user.id,
        parseInt(page),
        parseInt(size)
      );
      res.json(activities);
    } catch (error) {
      res.status(500).json({ error: 'Failed to fetch friends activities' });
    }
  }
}

module.exports = new ActivityController();
```

### Activity Service (Business Logic)
```javascript
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

class ActivityService {
  async createActivity(activityData) {
    const { locations, ...activity } = activityData;
    
    return await prisma.activity.create({
      data: {
        ...activity,
        locations: {
          create: locations || []
        }
      },
      include: {
        user: {
          select: { id: true, firstname: true, lastname: true, username: true }
        },
        locations: true,
        _count: {
          select: { likes: true, comments: true }
        }
      }
    });
  }

  async getUserActivities(userId, page, size) {
    const activities = await prisma.activity.findMany({
      where: { userId },
      skip: page * size,
      take: size,
      orderBy: { createdAt: 'desc' },
      include: {
        user: {
          select: { id: true, firstname: true, lastname: true, username: true }
        },
        _count: {
          select: { likes: true, comments: true }
        }
      }
    });

    const total = await prisma.activity.count({ where: { userId } });
    
    return {
      content: activities,
      totalElements: total,
      totalPages: Math.ceil(total / size),
      number: page
    };
  }

  async getFriendsActivities(userId, page, size) {
    // Get user's friends
    const friendRequests = await prisma.friendRequest.findMany({
      where: {
        OR: [
          { requesterId: userId, status: 'ACCEPTED' },
          { receiverId: userId, status: 'ACCEPTED' }
        ]
      }
    });

    const friendIds = friendRequests.map(req => 
      req.requesterId === userId ? req.receiverId : req.requesterId
    );
    friendIds.push(userId); // Include own activities

    const activities = await prisma.activity.findMany({
      where: { userId: { in: friendIds } },
      skip: page * size,
      take: size,
      orderBy: { createdAt: 'desc' },
      include: {
        user: {
          select: { id: true, firstname: true, lastname: true, username: true }
        },
        _count: {
          select: { likes: true, comments: true }
        }
      }
    });

    const total = await prisma.activity.count({
      where: { userId: { in: friendIds } }
    });

    return {
      content: activities,
      totalElements: total,
      totalPages: Math.ceil(total / size),
      number: page
    };
  }
}

module.exports = new ActivityService();
```

## 7. API Endpoints (Core Routes)

### Authentication Routes
```javascript
// POST /api/auth/register
{
  "firstname": "John",
  "lastname": "Doe", 
  "username": "john@example.com",
  "password": "password123"
}

// POST /api/auth/login
{
  "username": "john@example.com",
  "password": "password123"
}
// Returns: { "accessToken": "jwt_token", "user": {...} }
```

### Activity Routes
```javascript
// GET /api/private/activity/all?page=0&size=20
// POST /api/private/activity
{
  "type": "RUNNING",
  "startDatetime": "2025-06-23T08:00:00.000Z",
  "endDatetime": "2025-06-23T08:30:00.000Z", 
  "distance": 5.2,
  "speed": 10.4,
  "time": 1800000,
  "locations": [
    {"latitude": 40.7128, "longitude": -74.0060},
    {"latitude": 40.7129, "longitude": -74.0061}
  ]
}

// GET /api/private/activity/friends?page=0&size=10
// DELETE /api/private/activity/{id}
```

### Social Routes
```javascript
// POST /api/private/friend-request/send/{userId}
// GET /api/private/friend-request/pending
// PUT /api/private/friend-request/accept/{requestId}
// PUT /api/private/friend-request/reject/{requestId}

// POST /api/private/activity/{id}/like
// DELETE /api/private/activity/{id}/like
// POST /api/private/activity/{id}/comment
{
  "content": "Great run!"
}
```

## 8. Testing Examples

### Unit Tests
```javascript
const request = require('supertest');
const app = require('../src/app');

describe('Authentication', () => {
  test('should register new user', async () => {
    const userData = {
      firstname: 'Test',
      lastname: 'User',
      username: 'test@example.com',
      password: 'password123'
    };

    const response = await request(app)
      .post('/api/auth/register')
      .send(userData)
      .expect(201);

    expect(response.body.message).toBe('User registered successfully');
  });

  test('should login with valid credentials', async () => {
    const loginData = {
      username: 'test@example.com',
      password: 'password123'
    };

    const response = await request(app)
      .post('/api/auth/login')
      .send(loginData)
      .expect(200);

    expect(response.body.accessToken).toBeDefined();
    expect(response.body.user.username).toBe('test@example.com');
  });
});
```

## 9. Environment Configuration

### .env file
```bash
# Database
DATABASE_URL="postgresql://username:password@localhost:5432/rythmrun"

# JWT
JWT_SECRET="your-super-secret-jwt-key"
JWT_EXPIRES_IN="24h"

# Server
PORT=8080
NODE_ENV="development"

# Email (optional)
SMTP_HOST="smtp.gmail.com"
SMTP_PORT=587
SMTP_USER="your-email@gmail.com"
SMTP_PASS="your-app-password"
```

## 10. Quick Setup Commands

```bash
# Initialize project
npm init -y
npm install express prisma @prisma/client bcryptjs jsonwebtoken multer cors helmet

# Setup database
npx prisma init
npx prisma migrate dev --name init
npx prisma generate

# Development
npm run dev

# Testing
npm test

# Build for production
npm run build
npm start
```

## 11. Resume Project Highlights

### Technical Skills Demonstrated
✅ **Node.js + TypeScript** - Modern backend development
✅ **Express.js** - RESTful API design and implementation
✅ **PostgreSQL + Prisma** - Database design and ORM usage
✅ **JWT Authentication** - Secure authentication system
✅ **Clean Architecture** - Scalable code organization
✅ **Testing** - Unit and integration tests
✅ **Security** - Password hashing, input validation, CORS
✅ **File Handling** - Image uploads and processing
✅ **API Documentation** - Swagger/OpenAPI specs

### Project Complexity (Perfect for Resume)
- **Real-time location tracking** data handling
- **Social networking features** (friends, likes, comments)
- **Complex database relationships** with proper constraints
- **Pagination and filtering** for large datasets  
- **File upload handling** for profile pictures
- **Comprehensive error handling** and validation
- **Production-ready setup** with Docker and environment configs

This backend project showcases modern Node.js development skills while being achievable as a personal project - perfect for your resume! 🚀
      .expect(200);

    expect(response.body.accessToken).toBeDefined();
    expect(response.body.user.username).toBe('test@example.com');
  });
});
```

## 9. Environment Configuration

### .env file
```bash
# Database
DATABASE_URL="postgresql://username:password@localhost:5432/rythmrun"

# JWT
JWT_SECRET="your-super-secret-jwt-key"
JWT_EXPIRES_IN="24h"

# Server
PORT=8080
NODE_ENV="development"

# Email (optional)
SMTP_HOST="smtp.gmail.com"
SMTP_PORT=587
SMTP_USER="your-email@gmail.com"
SMTP_PASS="your-app-password"
```

## 10. Quick Setup Commands

```bash
# Initialize project
npm init -y
npm install express prisma @prisma/client bcryptjs jsonwebtoken multer cors helmet

# Setup database
npx prisma init
npx prisma migrate dev --name init
npx prisma generate

# Development
npm run dev

# Testing
npm test

# Build for production
npm run build
npm start
```

## 11. Resume Project Highlights

### Technical Skills Demonstrated
✅ **Node.js + TypeScript** - Modern backend development
✅ **Express.js** - RESTful API design and implementation
✅ **PostgreSQL + Prisma** - Database design and ORM usage
✅ **JWT Authentication** - Secure authentication system
✅ **Clean Architecture** - Scalable code organization
✅ **Testing** - Unit and integration tests
✅ **Security** - Password hashing, input validation, CORS
✅ **File Handling** - Image uploads and processing
✅ **API Documentation** - Swagger/OpenAPI specs

### Project Complexity (Perfect for Resume)
- **Real-time location tracking** data handling
- **Social networking features** (friends, likes, comments)
- **Complex database relationships** with proper constraints
- **Pagination and filtering** for large datasets  
- **File upload handling** for profile pictures
- **Comprehensive error handling** and validation
- **Production-ready setup** with Docker and environment configs

This backend project showcases modern Node.js development skills while being achievable as a personal project - perfect for your resume! 🚀
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_created_at ON users(created_at);

-- Constraints
ALTER TABLE users ADD CONSTRAINT chk_username_length CHECK (LENGTH(username) >= 3);
ALTER TABLE users ADD CONSTRAINT chk_password_length CHECK (LENGTH(password) >= 8);
```

#### Activities Table (`activities`)

```sql
CREATE TABLE activities (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL CHECK (type IN ('RUNNING', 'CYCLING')),
    start_datetime TIMESTAMP NOT NULL,
    end_datetime TIMESTAMP NOT NULL,
    global_distance DOUBLE PRECISION CHECK (global_distance >= 0),
    speed DOUBLE PRECISION CHECK (speed >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_activities_user_id ON activities(user_id);
CREATE INDEX idx_activities_start_datetime ON activities(start_datetime DESC);
CREATE INDEX idx_activities_type ON activities(type);
CREATE INDEX idx_activities_user_start ON activities(user_id, start_datetime DESC);

-- Constraints
ALTER TABLE activities ADD CONSTRAINT chk_datetime_order
    CHECK (end_datetime > start_datetime);
```

#### Locations Table (`locations`)

```sql
CREATE TABLE locations (
    id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    datetime TIMESTAMP NOT NULL,
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude >= -90 AND latitude <= 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude >= -180 AND longitude <= 180),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_locations_activity_id ON locations(activity_id);
CREATE INDEX idx_locations_datetime ON locations(datetime);
CREATE INDEX idx_locations_activity_datetime ON locations(activity_id, datetime);
```

#### Activity Comments Table (`activity_comments`)

```sql
CREATE TABLE activity_comments (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_id BIGINT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    content TEXT NOT NULL CHECK (LENGTH(TRIM(content)) > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_activity_comments_activity_id ON activity_comments(activity_id);
CREATE INDEX idx_activity_comments_user_id ON activity_comments(user_id);
CREATE INDEX idx_activity_comments_created_at ON activity_comments(created_at ASC);
```

#### Activity Likes Table (`activity_likes`)

```sql
CREATE TABLE activity_likes (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_id BIGINT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    like_datetime TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, activity_id)
);

-- Indexes for performance
CREATE INDEX idx_activity_likes_activity_id ON activity_likes(activity_id);
CREATE INDEX idx_activity_likes_user_id ON activity_likes(user_id);
```

#### Friend Requests Table (`friend_requests`)

```sql
CREATE TABLE friend_requests (
    id BIGSERIAL PRIMARY KEY,
    sender_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'ACCEPTED', 'REJECTED')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sender_id, receiver_id)
);

-- Indexes for performance
CREATE INDEX idx_friend_requests_sender_id ON friend_requests(sender_id);
CREATE INDEX idx_friend_requests_receiver_id ON friend_requests(receiver_id);
CREATE INDEX idx_friend_requests_status ON friend_requests(status);

-- Constraints
ALTER TABLE friend_requests ADD CONSTRAINT chk_not_self_request
    CHECK (sender_id != receiver_id);
```

#### Refresh Tokens Table (`refresh_tokens`)

```sql
CREATE TABLE refresh_tokens (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(512) NOT NULL UNIQUE,
    expiry_date TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id)
);

-- Indexes for performance
CREATE INDEX idx_refresh_tokens_token ON refresh_tokens(token);
CREATE INDEX idx_refresh_tokens_expiry ON refresh_tokens(expiry_date);
```

### Database Relationships Diagram

```
users (1) ----< activities (1) ----< locations (*)
  |                   |
  |                   +----< activity_comments (*)
  |                   |
  |                   +----< activity_likes (*)
  |
  +----< friend_requests (sender) (*)
  |
  +----< friend_requests (receiver) (*)
  |
  +----< refresh_tokens (1:1)
```

## 3. API Endpoints - Complete Specification

### Authentication Endpoints

#### User Registration

- **Endpoint**: `POST /api/user/register`
- **Content-Type**: `application/json`
- **Authentication**: None required

**Request Body**:

```json
{
  "firstname": "John", // Optional, string, max 255 chars
  "lastname": "Doe", // Optional, string, max 255 chars
  "username": "john.doe@email.com", // Required, string, unique, min 3 chars
  "password": "SecurePass123" // Required, string, min 8 chars
}
```

**Success Response** (201 Created):

```json
{
  "id": 123
}
```

**Error Responses**:

```json
// 409 Conflict - Username already exists
{
  "error": "CONFLICT",
  "message": "An account already exists for this email",
  "statusCode": 409,
  "timestamp": "2025-06-23T10:30:00.000Z"
}

// 422 Validation Error
{
  "error": "VALIDATION_ERROR",
  "message": "Validation failed",
  "statusCode": 422,
  "details": [
    {
      "field": "password",
      "message": "Password must be at least 8 characters long"
    }
  ],
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### User Login

- **Endpoint**: `POST /api/user/login`
- **Content-Type**: `application/json`
- **Authentication**: None required

**Request Body**:

```json
{
  "username": "john.doe@email.com",
  "password": "SecurePass123"
}
```

**Success Response** (200 OK):

```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "refresh_token_string_here",
  "tokenType": "Bearer",
  "expiresIn": 3600,
  "user": {
    "id": 123,
    "username": "john.doe@email.com",
    "firstname": "John",
    "lastname": "Doe"
  }
}
```

**Error Responses**:

```json
// 401 Unauthorized - Invalid credentials
{
  "error": "UNAUTHORIZED",
  "message": "Invalid username or password",
  "statusCode": 401,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Token Refresh

- **Endpoint**: `POST /api/user/refreshToken`
- **Content-Type**: `application/json`

**Request Body**:

```json
{
  "token": "refresh_token_string_here"
}
```

**Success Response** (200 OK):

```json
{
  "token": "new_access_token_here"
}
```

**Error Responses**:

```json
// 401 Unauthorized - Invalid or expired refresh token
{
  "error": "UNAUTHORIZED",
  "message": "Invalid or expired refresh token",
  "statusCode": 401,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Logout

- **Endpoint**: `POST /api/user/logout`
- **Headers**: `Authorization: Bearer <access_token>`

**Success Response** (200 OK):

```json
{
  "message": "Successfully logged out"
}
```

#### Password Reset

- **Endpoint**: `POST /api/user/sendNewPasswordByMail`
- **Content-Type**: `application/json`

**Request Body**:

```json
{
  "email": "john.doe@email.com"
}
```

**Success Response** (200 OK):

```json
{
  "message": "Password reset email sent successfully"
}
```

### Protected User Endpoints

#### Edit Password

- **Endpoint**: `PUT /api/private/user/editPassword`
- **Headers**: `Authorization: Bearer <token>`
- **Content-Type**: `application/json`

**Request Body**:

```json
{
  "currentPassword": "OldPassword123",
  "password": "NewPassword456"
}
```

**Success Response** (200 OK):

```json
{
  "id": 123
}
```

**Error Responses**:

```json
// 401 Unauthorized - Current password incorrect
{
  "error": "UNAUTHORIZED",
  "message": "The current password is incorrect",
  "statusCode": 401,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Edit Profile

- **Endpoint**: `PUT /api/private/user/editProfile`
- **Headers**: `Authorization: Bearer <token>`
- **Content-Type**: `application/json`

**Request Body**:

```json
{
  "firstname": "John Updated",
  "lastname": "Doe Updated"
}
```

**Success Response** (200 OK):

```json
{
  "id": 123
}
```

#### Delete User

- **Endpoint**: `DELETE /api/private/user`
- **Headers**: `Authorization: Bearer <token>`

**Success Response** (200 OK):

```json
{
  "message": "User successfully deleted"
}
```

#### User Search

- **Endpoint**: `GET /api/private/user/search`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `searchText` (required, min 2 characters)

**Example Request**: `GET /api/private/user/search?searchText=john`

**Success Response** (200 OK):

```json
[
  {
    "id": 123,
    "firstname": "John",
    "lastname": "Doe",
    "username": "john.doe@email.com"
  },
  {
    "id": 124,
    "firstname": "Johnny",
    "lastname": "Smith",
    "username": "johnny.smith@email.com"
  }
]
```

#### Upload Profile Picture

- **Endpoint**: `POST /api/private/user/picture/upload`
- **Headers**: `Authorization: Bearer <token>`
- **Content-Type**: `multipart/form-data`
- **Body**: Form data with `file` field (max 10MB, image formats only)

**Success Response** (200 OK):

```json
{
  "message": "Successfully uploaded file"
}
```

**Error Responses**:

```json
// 400 Bad Request - File too large or invalid format
{
  "error": "BAD_REQUEST",
  "message": "Failed to upload the profile picture",
  "statusCode": 400,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Download Profile Picture

- **Endpoint**: `GET /api/user/picture/download/:id`
- **Authentication**: None required
- **Path Parameters**: `id` (user ID)

**Success Response** (200 OK):

- **Headers**: `Content-Type: image/jpeg` (or appropriate image type)
- **Body**: Binary image data

**Error Responses**:

```json
// 404 Not Found - User or picture not found
{
  "error": "NOT_FOUND",
  "message": "User or profile picture not found",
  "statusCode": 404,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

### Activity Endpoints

#### Get All User Activities

- **Endpoint**: `GET /api/private/activity/all`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**:
  - `page` (optional, default: 0)
  - `size` (optional, default: 10, max: 50)

**Example Request**: `GET /api/private/activity/all?page=0&size=20`

**Success Response** (200 OK):

```json
{
  "content": [
    {
      "id": 456,
      "type": "RUNNING",
      "startDatetime": "2025-06-23T08:00:00.000Z",
      "endDatetime": "2025-06-23T08:30:00.000Z",
      "distance": 5.2,
      "speed": 10.4,
      "time": 1800000,
      "user": {
        "id": 123,
        "firstname": "John",
        "lastname": "Doe",
        "username": "john.doe@email.com"
      },
      "likesCount": 5,
      "hasCurrentUserLiked": false,
      "comments": [
        {
          "id": 789,
          "content": "Great run!",
          "createdAt": "2025-06-23T08:35:00.000Z",
          "user": {
            "id": 124,
            "firstname": "Jane",
            "lastname": "Smith",
            "username": "jane.smith@email.com"
          }
        }
      ]
    }
  ],
  "pageable": {
    "page": 0,
    "size": 20,
    "totalElements": 45,
    "totalPages": 3,
    "isFirst": true,
    "isLast": false
  }
}
```

#### Get Mine and Friends Activities

- **Endpoint**: `GET /api/private/activity/friends`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: Same as above
- **Description**: Returns activities from the authenticated user and their accepted friends
- **Response Format**: Same as "Get All User Activities"

#### Get User's Activities

- **Endpoint**: `GET /api/private/activity/user/:id`
- **Headers**: `Authorization: Bearer <token>`
- **Path Parameters**: `id` (user ID)
- **Query Parameters**: Same as above
- **Description**: Returns activities for a specific user (only if they are friends or it's the current user)
- **Response Format**: Same as "Get All User Activities"

**Error Responses**:

```json
// 403 Forbidden - Not friends with the user
{
  "error": "FORBIDDEN",
  "message": "You don't have the right to retrieve this user's activities",
  "statusCode": 403,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Get Activity by ID

- **Endpoint**: `GET /api/private/activity/:id`
- **Headers**: `Authorization: Bearer <token>`
- **Path Parameters**: `id` (activity ID)

**Success Response** (200 OK):

```json
{
  "id": 456,
  "type": "RUNNING",
  "startDatetime": "2025-06-23T08:00:00.000Z",
  "endDatetime": "2025-06-23T08:30:00.000Z",
  "distance": 5.2,
  "speed": 10.4,
  "time": 1800000,
  "user": {
    "id": 123,
    "firstname": "John",
    "lastname": "Doe",
    "username": "john.doe@email.com"
  },
  "locations": [
    {
      "id": 1001,
      "datetime": "2025-06-23T08:00:00.000Z",
      "latitude": 40.7128,
      "longitude": -74.006
    },
    {
      "id": 1002,
      "datetime": "2025-06-23T08:01:00.000Z",
      "latitude": 40.7129,
      "longitude": -74.0061
    }
  ],
  "likesCount": 5,
  "hasCurrentUserLiked": false,
  "comments": [
    {
      "id": 789,
      "content": "Great run!",
      "createdAt": "2025-06-23T08:35:00.000Z",
      "user": {
        "id": 124,
        "firstname": "Jane",
        "lastname": "Smith",
        "username": "jane.smith@email.com"
      }
    }
  ]
}
```

#### Create Activity

- **Endpoint**: `POST /api/private/activity/`
- **Headers**: `Authorization: Bearer <token>`
- **Content-Type**: `application/json`

**Request Body**:

```json
{
  "type": "RUNNING",
  "startDatetime": "2025-06-23T08:00:00.000Z",
  "endDatetime": "2025-06-23T08:30:00.000Z",
  "distance": 5.2,
  "speed": 10.4,
  "locations": [
    {
      "datetime": "2025-06-23T08:00:00.000Z",
      "latitude": 40.7128,
      "longitude": -74.006
    },
    {
      "datetime": "2025-06-23T08:01:00.000Z",
      "latitude": 40.7129,
      "longitude": -74.0061
    }
  ]
}
```

**Success Response** (201 Created):

```json
{
  "id": 456,
  "type": "RUNNING",
  "startDatetime": "2025-06-23T08:00:00.000Z",
  "endDatetime": "2025-06-23T08:30:00.000Z",
  "distance": 5.2,
  "speed": 10.4,
  "time": 1800000,
  "user": {
    "id": 123,
    "firstname": "John",
    "lastname": "Doe",
    "username": "john.doe@email.com"
  },
  "likesCount": 0,
  "hasCurrentUserLiked": false,
  "comments": []
}
```

**Validation Rules**:

- `type`: Must be "RUNNING" or "CYCLING"
- `startDatetime`: Required, must be valid ISO date
- `endDatetime`: Required, must be after startDatetime
- `distance`: Optional, must be positive number
- `speed`: Optional, must be positive number
- `locations`: Optional array, each location needs valid latitude (-90 to 90) and longitude (-180 to 180)

#### Update Activity

- **Endpoint**: `PUT /api/private/activity/`
- **Headers**: `Authorization: Bearer <token>`
- **Content-Type**: `application/json`
- **Description**: Only the activity owner can update their activity

**Request Body**: Same as Create Activity, but include `id` field

**Success Response** (200 OK): Same format as Create Activity response

**Error Responses**:

```json
// 403 Forbidden - Not the activity owner
{
  "error": "FORBIDDEN",
  "message": "You don't have the right to update this activity",
  "statusCode": 403,
  "timestamp": "2025-06-23T10:30:00.000Z"
}

// 404 Not Found - Activity doesn't exist
{
  "error": "NOT_FOUND",
  "message": "Activity with id: 456 is not available",
  "statusCode": 404,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Delete Activity

- **Endpoint**: `DELETE /api/private/activity/`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `id` (activity ID)

**Example Request**: `DELETE /api/private/activity/?id=456`

**Success Response** (200 OK):

```json
{
  "message": "Activity successfully deleted"
}
```

#### Like Activity

- **Endpoint**: `POST /api/private/activity/like`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `id` (activity ID)

**Example Request**: `POST /api/private/activity/like?id=456`

**Success Response** (200 OK):

```json
{
  "message": "Activity liked successfully"
}
```

**Error Responses**:

```json
// 404 Not Found - Activity doesn't exist
{
  "error": "NOT_FOUND",
  "message": "Activity not found",
  "statusCode": 404,
  "timestamp": "2025-06-23T10:30:00.000Z"
}

// 409 Conflict - Already liked
{
  "error": "CONFLICT",
  "message": "Activity already liked by user",
  "statusCode": 409,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Unlike Activity

- **Endpoint**: `POST /api/private/activity/dislike`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `id` (activity ID)

**Success Response** (200 OK):

```json
{
  "message": "Activity disliked successfully"
}
```

### Activity Comments

#### Create Comment

- **Endpoint**: `POST /api/private/activity/comment`
- **Headers**: `Authorization: Bearer <token>`
- **Content-Type**: `application/x-www-form-urlencoded`
- **Body Parameters**:
  - `comment` (required, non-empty string)
  - `activityId` (required, valid activity ID)

**Request Body**:

```
comment=Great%20run!&activityId=456
```

**Success Response** (200 OK):

```json
{
  "id": 789,
  "content": "Great run!",
  "createdAt": "2025-06-23T08:35:00.000Z",
  "user": {
    "id": 123,
    "firstname": "John",
    "lastname": "Doe",
    "username": "john.doe@email.com"
  }
}
```

**Error Responses**:

```json
// 400 Bad Request - Empty comment
{
  "error": "BAD_REQUEST",
  "message": "Comment content cannot be empty",
  "statusCode": 400,
  "timestamp": "2025-06-23T10:30:00.000Z"
}

// 404 Not Found - Activity doesn't exist
{
  "error": "NOT_FOUND",
  "message": "Activity not found",
  "statusCode": 404,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Update Comment

- **Endpoint**: `PUT /api/private/activity/comment`
- **Headers**: `Authorization: Bearer <token>`
- **Content-Type**: `application/x-www-form-urlencoded`
- **Body Parameters**:
  - `id` (required, comment ID)
  - `comment` (required, updated content)

**Success Response** (200 OK): Same format as Create Comment

**Error Responses**:

```json
// 403 Forbidden - Not the comment owner
{
  "error": "FORBIDDEN",
  "message": "You don't have the right to update this comment",
  "statusCode": 403,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Delete Comment

- **Endpoint**: `DELETE /api/private/activity/comment`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `id` (comment ID)

**Success Response** (200 OK):

```json
{
  "message": "Comment successfully deleted"
}
```

### Friend Management

#### Get Pending Friend Requests

- **Endpoint**: `GET /api/private/friends/pending`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**:
  - `page` (optional, default: 0)
  - `size` (optional, default: 10)

**Success Response** (200 OK):

```json
{
  "content": [
    {
      "id": 101,
      "firstname": "Jane",
      "lastname": "Smith",
      "username": "jane.smith@email.com"
    },
    {
      "id": 102,
      "firstname": "Bob",
      "lastname": "Johnson",
      "username": "bob.johnson@email.com"
    }
  ],
  "pageable": {
    "page": 0,
    "size": 10,
    "totalElements": 2,
    "totalPages": 1,
    "isFirst": true,
    "isLast": true
  }
}
```

#### Get Friend Request Status

- **Endpoint**: `GET /api/private/friends/getStatus`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `userId` (required, target user ID)

**Success Response** (200 OK):

```json
{
  "id": 301,
  "status": "PENDING",
  "sender": {
    "id": 123,
    "firstname": "John",
    "lastname": "Doe",
    "username": "john.doe@email.com"
  },
  "receiver": {
    "id": 124,
    "firstname": "Jane",
    "lastname": "Smith",
    "username": "jane.smith@email.com"
  },
  "createdAt": "2025-06-23T10:00:00.000Z"
}
```

**Error Responses**:

```json
// 404 Not Found - No friend request exists
{
  "error": "NOT_FOUND",
  "message": "Friend request not found",
  "statusCode": 404,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Send Friend Request

- **Endpoint**: `POST /api/private/friends/sendRequest`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `receiverId` (required, target user ID)

**Success Response** (201 Created):

```json
{
  "id": 301
}
```

**Error Responses**:

```json
// 400 Bad Request - Cannot send request to yourself
{
  "error": "BAD_REQUEST",
  "message": "Cannot send friend request to yourself",
  "statusCode": 400,
  "timestamp": "2025-06-23T10:30:00.000Z"
}

// 409 Conflict - Request already exists
{
  "error": "CONFLICT",
  "message": "Friend request already exists",
  "statusCode": 409,
  "timestamp": "2025-06-23T10:30:00.000Z"
}

// 404 Not Found - User doesn't exist
{
  "error": "NOT_FOUND",
  "message": "User not found",
  "statusCode": 404,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

#### Accept Friend Request

- **Endpoint**: `POST /api/private/friends/acceptRequest`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `userId` (required, sender user ID)

**Success Response** (200 OK):

```json
{
  "id": 301,
  "status": "ACCEPTED",
  "sender": {
    "id": 124,
    "firstname": "Jane",
    "lastname": "Smith",
    "username": "jane.smith@email.com"
  },
  "receiver": {
    "id": 123,
    "firstname": "John",
    "lastname": "Doe",
    "username": "john.doe@email.com"
  },
  "updatedAt": "2025-06-23T10:30:00.000Z"
}
```

#### Reject Friend Request

- **Endpoint**: `POST /api/private/friends/rejectRequest`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `userId` (required, sender user ID)

**Success Response** (200 OK): Same format as Accept Friend Request with `status: "REJECTED"`

#### Cancel Friend Request

- **Endpoint**: `POST /api/private/friends/cancelRequest`
- **Headers**: `Authorization: Bearer <token>`
- **Query Parameters**: `userId` (required, receiver user ID)
- **Description**: Cancel a friend request you sent

**Success Response** (200 OK): Same format as Accept Friend Request with original status

**Common Friend Request Error Responses**:

```json
// 404 Not Found - Friend request doesn't exist
{
  "error": "NOT_FOUND",
  "message": "Friend request not found",
  "statusCode": 404,
  "timestamp": "2025-06-23T10:30:00.000Z"
}

// 403 Forbidden - Not authorized for this action
{
  "error": "FORBIDDEN",
  "message": "Not authorized to perform this action",
  "statusCode": 403,
  "timestamp": "2025-06-23T10:30:00.000Z"
}
```

## 4. Data Models & DTOs - Complete Type Definitions

### Core Entity Models

#### User Entity

```typescript
interface User {
  id: number;
  firstname?: string;
  lastname?: string;
  username: string;
  password: string; // Hashed with bcrypt
  profilePicture?: Buffer; // Binary image data
  profilePictureType?: string; // MIME type (e.g., 'image/jpeg')
  createdAt: Date;
  updatedAt: Date;

  // Relations (populated when needed)
  activities?: Activity[];
  sentFriendRequests?: FriendRequest[];
  receivedFriendRequests?: FriendRequest[];
  refreshToken?: RefreshToken;
  comments?: ActivityComment[];
  likes?: ActivityLike[];
}
```

#### Activity Entity

```typescript
interface Activity {
  id: number;
  userId: number;
  type: ActivityType;
  startDatetime: Date;
  endDatetime: Date;
  distance?: number; // In kilometers
  speed?: number; // In km/h
  createdAt: Date;
  updatedAt: Date;

  // Relations
  user?: User;
  locations?: Location[];
  comments?: ActivityComment[];
  likes?: ActivityLike[];
}

enum ActivityType {
  RUNNING = "RUNNING",
  CYCLING = "CYCLING",
}
```

#### Location Entity

```typescript
interface Location {
  id: number;
  activityId: number;
  datetime: Date;
  latitude: number; // Range: -90 to 90
  longitude: number; // Range: -180 to 180
  createdAt: Date;

  // Relations
  activity?: Activity;
}
```

#### ActivityComment Entity

```typescript
interface ActivityComment {
  id: number;
  userId: number;
  activityId: number;
  content: string;
  createdAt: Date;
  updatedAt: Date;

  // Relations
  user?: User;
  activity?: Activity;
}
```

#### ActivityLike Entity

```typescript
interface ActivityLike {
  id: number;
  userId: number;
  activityId: number;
  likeDatetime: Date;

  // Relations
  user?: User;
  activity?: Activity;
}
```

#### FriendRequest Entity

```typescript
interface FriendRequest {
  id: number;
  senderId: number;
  receiverId: number;
  status: FriendRequestStatus;
  createdAt: Date;
  updatedAt: Date;

  // Relations
  sender?: User;
  receiver?: User;
}

enum FriendRequestStatus {
  PENDING = "PENDING",
  ACCEPTED = "ACCEPTED",
  REJECTED = "REJECTED",
}
```

#### RefreshToken Entity

```typescript
interface RefreshToken {
  id: number;
  userId: number;
  token: string;
  expiryDate: Date;
  createdAt: Date;

  // Relations
  user?: User;
}
```

### Request DTOs (Input Validation)

#### User Registration DTO

```typescript
interface UserRegistrationDto {
  firstname?: string; // Optional, max 255 chars
  lastname?: string; // Optional, max 255 chars
  username: string; // Required, unique, min 3 chars, email format
  password: string; // Required, min 8 chars, strong password
}

// Joi Validation Schema
const userRegistrationSchema = Joi.object({
  firstname: Joi.string().max(255).optional().allow(""),
  lastname: Joi.string().max(255).optional().allow(""),
  username: Joi.string().email().min(3).max(255).required(),
  password: Joi.string()
    .min(8)
    .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .required()
    .messages({
      "string.pattern.base":
        "Password must contain at least one uppercase letter, one lowercase letter, and one number",
    }),
});
```

#### User Login DTO

```typescript
interface UserLoginDto {
  username: string; // Required, email format
  password: string; // Required
}

const userLoginSchema = Joi.object({
  username: Joi.string().email().required(),
  password: Joi.string().required(),
});
```

#### Edit Password DTO

```typescript
interface EditPasswordDto {
  currentPassword: string; // Required
  password: string; // Required, min 8 chars, strong password
}

const editPasswordSchema = Joi.object({
  currentPassword: Joi.string().required(),
  password: Joi.string()
    .min(8)
    .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    .required(),
});
```

#### Edit Profile DTO

```typescript
interface EditProfileDto {
  firstname?: string; // Optional, max 255 chars
  lastname?: string; // Optional, max 255 chars
}

const editProfileSchema = Joi.object({
  firstname: Joi.string().max(255).optional().allow(""),
  lastname: Joi.string().max(255).optional().allow(""),
});
```

#### Activity Creation DTO

```typescript
interface ActivityCreateDto {
  type: ActivityType; // Required, 'RUNNING' or 'CYCLING'
  startDatetime: Date; // Required, ISO date string
  endDatetime: Date; // Required, must be after startDatetime
  distance?: number; // Optional, positive number
  speed?: number; // Optional, positive number
  locations?: LocationCreateDto[]; // Optional array
}

interface LocationCreateDto {
  datetime: Date; // Required, ISO date string
  latitude: number; // Required, -90 to 90
  longitude: number; // Required, -180 to 180
}

const activityCreateSchema = Joi.object({
  type: Joi.string().valid("RUNNING", "CYCLING").required(),
  startDatetime: Joi.date().iso().required(),
  endDatetime: Joi.date().iso().greater(Joi.ref("startDatetime")).required(),
  distance: Joi.number().positive().optional(),
  speed: Joi.number().positive().optional(),
  locations: Joi.array()
    .items(
      Joi.object({
        datetime: Joi.date().iso().required(),
        latitude: Joi.number().min(-90).max(90).required(),
        longitude: Joi.number().min(-180).max(180).required(),
      })
    )
    .optional(),
});
```

#### Activity Update DTO

```typescript
interface ActivityUpdateDto extends ActivityCreateDto {
  id: number; // Required for update
}

const activityUpdateSchema = activityCreateSchema.keys({
  id: Joi.number().integer().positive().required(),
});
```

#### Comment Creation DTO

```typescript
interface CommentCreateDto {
  comment: string; // Required, non-empty, max 1000 chars
  activityId: number; // Required, valid activity ID
}

const commentCreateSchema = Joi.object({
  comment: Joi.string().trim().min(1).max(1000).required(),
  activityId: Joi.number().integer().positive().required(),
});
```

#### Comment Update DTO

```typescript
interface CommentUpdateDto {
  id: number; // Required, comment ID
  comment: string; // Required, non-empty, max 1000 chars
}

const commentUpdateSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
  comment: Joi.string().trim().min(1).max(1000).required(),
});
```

### Response DTOs (Output)

#### User Search DTO

```typescript
interface UserSearchDto {
  id: number;
  firstname?: string;
  lastname?: string;
  username: string;
}
```

#### User Profile DTO

```typescript
interface UserProfileDto {
  id: number;
  username: string;
  firstname?: string;
  lastname?: string;
  createdAt: Date;
}
```

#### Activity Response DTO

```typescript
interface ActivityResponseDto {
  id: number;
  type: ActivityType;
  startDatetime: Date;
  endDatetime: Date;
  distance?: number;
  speed?: number;
  time: number; // Duration in milliseconds
  user: UserSearchDto;
  likesCount: number;
  hasCurrentUserLiked: boolean;
  comments?: ActivityCommentResponseDto[];
  locations?: LocationResponseDto[];
}
```

#### Location Response DTO

```typescript
interface LocationResponseDto {
  id: number;
  datetime: Date;
  latitude: number;
  longitude: number;
}
```

#### Activity Comment Response DTO

```typescript
interface ActivityCommentResponseDto {
  id: number;
  content: string;
  createdAt: Date;
  user: UserSearchDto;
}
```

#### Friend Request Response DTO

```typescript
interface FriendRequestResponseDto {
  id: number;
  status: FriendRequestStatus;
  sender: UserSearchDto;
  receiver: UserSearchDto;
  createdAt: Date;
  updatedAt?: Date;
}
```

#### Paginated Response DTO

```typescript
interface PageResponseDto<T> {
  content: T[];
  pageable: {
    page: number;
    size: number;
    totalElements: number;
    totalPages: number;
    isFirst: boolean;
    isLast: boolean;
  };
}
```

#### Authentication Response DTO

```typescript
interface AuthResponseDto {
  accessToken: string;
  refreshToken: string;
  tokenType: "Bearer";
  expiresIn: number; // Seconds until access token expires
  user: UserProfileDto;
}
```

#### Refresh Token Response DTO

```typescript
interface RefreshTokenResponseDto {
  token: string; // New access token
}
```

#### Error Response DTO

```typescript
interface ErrorResponseDto {
  error: string; // Error code (e.g., 'VALIDATION_ERROR')
  message: string; // Human readable message
  statusCode: number; // HTTP status code
  timestamp: string; // ISO date string
  details?: ValidationErrorDetail[]; // For validation errors
}

interface ValidationErrorDetail {
  field: string; // Field name that failed validation
  message: string; // Specific validation error message
}
```

### Business Logic Models

#### JWT Payload

```typescript
interface JwtPayload {
  userId: number;
  username: string;
  iat: number; // Issued at (timestamp)
  exp: number; // Expires at (timestamp)
}
```

#### Activity Metrics Calculation

```typescript
interface ActivityMetrics {
  duration: number; // In milliseconds
  averageSpeed: number; // In km/h
  totalDistance: number; // In kilometers
  maxSpeed: number; // In km/h
  minSpeed: number; // In km/h
}

// Calculation functions
function calculateActivityMetrics(
  activity: Activity,
  locations: Location[]
): ActivityMetrics {
  const duration =
    activity.endDatetime.getTime() - activity.startDatetime.getTime();

  let totalDistance = 0;
  let speeds: number[] = [];

  if (locations.length > 1) {
    for (let i = 1; i < locations.length; i++) {
      const distance = calculateDistanceBetweenPoints(
        locations[i - 1].latitude,
        locations[i - 1].longitude,
        locations[i].latitude,
        locations[i].longitude
      );
      totalDistance += distance;

      const timeDiff =
        locations[i].datetime.getTime() - locations[i - 1].datetime.getTime();
      const speed = (distance / timeDiff) * 3600000; // Convert to km/h
      speeds.push(speed);
    }
  }

  const averageSpeed =
    activity.distance && duration
      ? (activity.distance / duration) * 3600000
      : speeds.length > 0
      ? speeds.reduce((sum, speed) => sum + speed, 0) / speeds.length
      : 0;

  return {
    duration,
    averageSpeed,
    totalDistance: activity.distance || totalDistance,
    maxSpeed: speeds.length > 0 ? Math.max(...speeds) : 0,
    minSpeed: speeds.length > 0 ? Math.min(...speeds) : 0,
  };
}

// Haversine formula for distance calculation
function calculateDistanceBetweenPoints(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371; // Earth's radius in kilometers
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}
```

#### Friend Relationship Helper

```typescript
interface FriendshipStatus {
  areFriends: boolean;
  pendingRequest?: {
    id: number;
    status: FriendRequestStatus;
    sentByCurrentUser: boolean;
  };
}

async function getFriendshipStatus(
  currentUserId: number,
  targetUserId: number
): Promise<FriendshipStatus> {
  // Implementation to check friendship status
  // Returns whether users are friends and any pending requests
}
```

### Database Query Interfaces

#### Pagination Parameters

```typescript
interface PaginationParams {
  page: number; // 0-based page number
  size: number; // Items per page (max 50)
  sort?: string; // Sort field
  order?: "ASC" | "DESC"; // Sort order
}

const paginationSchema = Joi.object({
  page: Joi.number().integer().min(0).default(0),
  size: Joi.number().integer().min(1).max(50).default(10),
  sort: Joi.string().optional(),
  order: Joi.string().valid("ASC", "DESC").default("DESC"),
});
```

#### Activity Query Filters

```typescript
interface ActivityQueryFilters extends PaginationParams {
  type?: ActivityType;
  startDate?: Date;
  endDate?: Date;
  minDistance?: number;
  maxDistance?: number;
  userId?: number; // For filtering by specific user
  friendsOnly?: boolean; // Include only friends' activities
}
```

#### User Search Filters

```typescript
interface UserSearchFilters extends PaginationParams {
  searchText: string; // Search in firstname, lastname, username
  excludeCurrentUser?: boolean;
  friendsOnly?: boolean;
}
```

## 5. Business Logic Requirements - Detailed Implementation

### Authentication & Security Logic

#### Password Management

```typescript
// Password hashing with bcrypt
import bcrypt from "bcrypt";

const SALT_ROUNDS = 12;

async function hashPassword(plainPassword: string): Promise<string> {
  return await bcrypt.hash(plainPassword, SALT_ROUNDS);
}

async function verifyPassword(
  plainPassword: string,
  hashedPassword: string
): Promise<boolean> {
  return await bcrypt.compare(plainPassword, hashedPassword);
}

// Password strength validation
function validatePasswordStrength(password: string): boolean {
  const hasUpperCase = /[A-Z]/.test(password);
  const hasLowerCase = /[a-z]/.test(password);
  const hasNumbers = /\d/.test(password);
  const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);
  const isLongEnough = password.length >= 8;

  return hasUpperCase && hasLowerCase && hasNumbers && isLongEnough;
}
```

#### JWT Token Management

```typescript
import jwt from "jsonwebtoken";

interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

// JWT Configuration
const JWT_SECRET = process.env.JWT_SECRET!;
const REFRESH_SECRET = process.env.REFRESH_TOKEN_SECRET!;
const ACCESS_TOKEN_EXPIRES = "1h";
const REFRESH_TOKEN_EXPIRES = "7d";

function generateTokenPair(user: User): TokenPair {
  const payload = {
    userId: user.id,
    username: user.username,
  };

  const accessToken = jwt.sign(payload, JWT_SECRET, {
    expiresIn: ACCESS_TOKEN_EXPIRES,
    issuer: "rythmrun-api",
    audience: "rythmrun-client",
  });

  const refreshToken = jwt.sign(payload, REFRESH_SECRET, {
    expiresIn: REFRESH_TOKEN_EXPIRES,
    issuer: "rythmrun-api",
    audience: "rythmrun-client",
  });

  return { accessToken, refreshToken };
}

function verifyAccessToken(token: string): JwtPayload {
  try {
    return jwt.verify(token, JWT_SECRET) as JwtPayload;
  } catch (error) {
    throw new Error("Invalid or expired access token");
  }
}

function verifyRefreshToken(token: string): JwtPayload {
  try {
    return jwt.verify(token, REFRESH_SECRET) as JwtPayload;
  } catch (error) {
    throw new Error("Invalid or expired refresh token");
  }
}

// Store refresh token in database
async function storeRefreshToken(userId: number, token: string): Promise<void> {
  const expiryDate = new Date();
  expiryDate.setDate(expiryDate.getDate() + 7); // 7 days from now

  await refreshTokenRepository.upsert({
    userId,
    token,
    expiryDate,
  });
}

// Clean up expired refresh tokens (run periodically)
async function cleanupExpiredTokens(): Promise<void> {
  await refreshTokenRepository.deleteExpired(new Date());
}
```

### Activity Calculation Logic

#### Distance and Speed Calculations

```typescript
interface ActivityCalculationResult {
  distance: number;
  averageSpeed: number;
  maxSpeed: number;
  duration: number;
}

function calculateActivityMetrics(
  activity: ActivityCreateDto
): ActivityCalculationResult {
  const duration =
    new Date(activity.endDatetime).getTime() -
    new Date(activity.startDatetime).getTime();

  if (!activity.locations || activity.locations.length < 2) {
    return {
      distance: activity.distance || 0,
      averageSpeed: activity.speed || 0,
      maxSpeed: activity.speed || 0,
      duration,
    };
  }

  let totalDistance = 0;
  let maxSpeed = 0;
  const speeds: number[] = [];

  for (let i = 1; i < activity.locations.length; i++) {
    const prev = activity.locations[i - 1];
    const curr = activity.locations[i];

    // Calculate distance between consecutive points
    const segmentDistance = calculateHaversineDistance(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude
    );
    totalDistance += segmentDistance;

    // Calculate speed for this segment
    const timeDiff =
      new Date(curr.datetime).getTime() - new Date(prev.datetime).getTime();
    if (timeDiff > 0) {
      const segmentSpeed = (segmentDistance / timeDiff) * 3600000; // km/h
      speeds.push(segmentSpeed);
      maxSpeed = Math.max(maxSpeed, segmentSpeed);
    }
  }

  const averageSpeed =
    totalDistance > 0 && duration > 0
      ? (totalDistance / duration) * 3600000
      : 0;

  return {
    distance: activity.distance || totalDistance,
    averageSpeed: activity.speed || averageSpeed,
    maxSpeed,
    duration,
  };
}

// Haversine formula for calculating distance between two GPS points
function calculateHaversineDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371; // Earth's radius in kilometers
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRadians(degrees: number): number {
  return degrees * (Math.PI / 180);
}

// Validate GPS coordinates
function validateCoordinates(latitude: number, longitude: number): boolean {
  return (
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
  );
}

// Filter out invalid or stationary GPS points
function filterValidLocations(
  locations: LocationCreateDto[]
): LocationCreateDto[] {
  if (locations.length < 2) return locations;

  const filtered: LocationCreateDto[] = [locations[0]]; // Always keep first point

  for (let i = 1; i < locations.length; i++) {
    const current = locations[i];
    const previous = filtered[filtered.length - 1];

    // Skip if coordinates are invalid
    if (!validateCoordinates(current.latitude, current.longitude)) {
      continue;
    }

    // Skip if point is too close to previous (less than 5 meters)
    const distance = calculateHaversineDistance(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude
    );

    if (distance >= 0.005) {
      // 5 meters minimum
      filtered.push(current);
    }
  }

  return filtered;
}
```

### Friend Management Logic

#### Friendship Status Checking

```typescript
enum FriendshipStatusEnum {
  NOT_FRIENDS = "NOT_FRIENDS",
  FRIENDS = "FRIENDS",
  REQUEST_SENT = "REQUEST_SENT",
  REQUEST_RECEIVED = "REQUEST_RECEIVED",
}

interface FriendshipInfo {
  status: FriendshipStatusEnum;
  friendRequestId?: number;
  canSendRequest: boolean;
  canViewActivities: boolean;
}

async function getFriendshipInfo(
  currentUserId: number,
  targetUserId: number
): Promise<FriendshipInfo> {
  if (currentUserId === targetUserId) {
    return {
      status: FriendshipStatusEnum.FRIENDS,
      canSendRequest: false,
      canViewActivities: true,
    };
  }

  const friendRequest = await friendRequestRepository.findBetweenUsers(
    currentUserId,
    targetUserId
  );

  if (!friendRequest) {
    return {
      status: FriendshipStatusEnum.NOT_FRIENDS,
      canSendRequest: true,
      canViewActivities: false,
    };
  }

  switch (friendRequest.status) {
    case FriendRequestStatus.ACCEPTED:
      return {
        status: FriendshipStatusEnum.FRIENDS,
        friendRequestId: friendRequest.id,
        canSendRequest: false,
        canViewActivities: true,
      };

    case FriendRequestStatus.PENDING:
      if (friendRequest.senderId === currentUserId) {
        return {
          status: FriendshipStatusEnum.REQUEST_SENT,
          friendRequestId: friendRequest.id,
          canSendRequest: false,
          canViewActivities: false,
        };
      } else {
        return {
          status: FriendshipStatusEnum.REQUEST_RECEIVED,
          friendRequestId: friendRequest.id,
          canSendRequest: false,
          canViewActivities: false,
        };
      }

    case FriendRequestStatus.REJECTED:
      return {
        status: FriendshipStatusEnum.NOT_FRIENDS,
        canSendRequest: true,
        canViewActivities: false,
      };

    default:
      return {
        status: FriendshipStatusEnum.NOT_FRIENDS,
        canSendRequest: true,
        canViewActivities: false,
      };
  }
}

// Check if user can view another user's activities
async function canViewUserActivities(
  viewerId: number,
  targetUserId: number
): Promise<boolean> {
  if (viewerId === targetUserId) return true;

  const friendshipInfo = await getFriendshipInfo(viewerId, targetUserId);
  return friendshipInfo.canViewActivities;
}

// Get all friends of a user
async function getUserFriends(userId: number): Promise<User[]> {
  const acceptedRequests = await friendRequestRepository.findAcceptedForUser(
    userId
  );

  const friendIds = acceptedRequests.map((request) =>
    request.senderId === userId ? request.receiverId : request.senderId
  );

  return await userRepository.findByIds(friendIds);
}
```

#### Friend Request Operations

```typescript
async function sendFriendRequest(
  senderId: number,
  receiverId: number
): Promise<FriendRequest> {
  // Validate users exist
  const [sender, receiver] = await Promise.all([
    userRepository.findById(senderId),
    userRepository.findById(receiverId),
  ]);

  if (!sender || !receiver) {
    throw new Error("User not found");
  }

  if (senderId === receiverId) {
    throw new Error("Cannot send friend request to yourself");
  }

  // Check if request already exists
  const existingRequest = await friendRequestRepository.findBetweenUsers(
    senderId,
    receiverId
  );
  if (existingRequest) {
    throw new Error("Friend request already exists");
  }

  // Create new friend request
  return await friendRequestRepository.create({
    senderId,
    receiverId,
    status: FriendRequestStatus.PENDING,
  });
}

async function acceptFriendRequest(
  receiverId: number,
  senderId: number
): Promise<FriendRequest> {
  const request = await friendRequestRepository.findPendingRequest(
    senderId,
    receiverId
  );

  if (!request) {
    throw new Error("Friend request not found");
  }

  if (request.receiverId !== receiverId) {
    throw new Error("Not authorized to accept this request");
  }

  return await friendRequestRepository.updateStatus(
    request.id,
    FriendRequestStatus.ACCEPTED
  );
}

async function rejectFriendRequest(
  receiverId: number,
  senderId: number
): Promise<FriendRequest> {
  const request = await friendRequestRepository.findPendingRequest(
    senderId,
    receiverId
  );

  if (!request) {
    throw new Error("Friend request not found");
  }

  if (request.receiverId !== receiverId) {
    throw new Error("Not authorized to reject this request");
  }

  return await friendRequestRepository.updateStatus(
    request.id,
    FriendRequestStatus.REJECTED
  );
}

async function cancelFriendRequest(
  senderId: number,
  receiverId: number
): Promise<void> {
  const request = await friendRequestRepository.findPendingRequest(
    senderId,
    receiverId
  );

  if (!request) {
    throw new Error("Friend request not found");
  }

  if (request.senderId !== senderId) {
    throw new Error("Not authorized to cancel this request");
  }

  await friendRequestRepository.delete(request.id);
}
```

### Activity Access Control

#### Activity Permissions

```typescript
enum ActivityPermission {
  READ = "READ",
  WRITE = "WRITE",
  DELETE = "DELETE",
}

async function checkActivityPermission(
  userId: number,
  activityId: number,
  permission: ActivityPermission
): Promise<boolean> {
  const activity = await activityRepository.findById(activityId);
  if (!activity) return false;

  // Owner has all permissions
  if (activity.userId === userId) return true;

  // For read permission, check if users are friends
  if (permission === ActivityPermission.READ) {
    return await canViewUserActivities(userId, activity.userId);
  }

  // Only owner can write/delete
  return false;
}

// Get activities visible to user (own + friends)
async function getVisibleActivities(
  userId: number,
  pagination: PaginationParams,
  includeOwnActivities: boolean = true
): Promise<PageResponseDto<Activity>> {
  const friends = await getUserFriends(userId);
  const friendIds = friends.map((friend) => friend.id);

  const visibleUserIds = includeOwnActivities
    ? [userId, ...friendIds]
    : friendIds;

  return await activityRepository.findByUserIds(visibleUserIds, pagination);
}
```

### Activity Interaction Logic

#### Like/Unlike Operations

```typescript
async function likeActivity(userId: number, activityId: number): Promise<void> {
  // Check if activity exists and user can view it
  const hasReadPermission = await checkActivityPermission(
    userId,
    activityId,
    ActivityPermission.READ
  );
  if (!hasReadPermission) {
    throw new Error("Activity not found or access denied");
  }

  // Check if already liked
  const existingLike = await activityLikeRepository.findByUserAndActivity(
    userId,
    activityId
  );
  if (existingLike) {
    throw new Error("Activity already liked by user");
  }

  // Create like
  await activityLikeRepository.create({
    userId,
    activityId,
    likeDatetime: new Date(),
  });
}

async function unlikeActivity(
  userId: number,
  activityId: number
): Promise<void> {
  const existingLike = await activityLikeRepository.findByUserAndActivity(
    userId,
    activityId
  );
  if (!existingLike) {
    throw new Error("Like not found");
  }

  await activityLikeRepository.delete(existingLike.id);
}

async function getActivityLikeInfo(
  userId: number,
  activityId: number
): Promise<{ count: number; hasCurrentUserLiked: boolean }> {
  const [count, userLike] = await Promise.all([
    activityLikeRepository.countByActivity(activityId),
    activityLikeRepository.findByUserAndActivity(userId, activityId),
  ]);

  return {
    count,
    hasCurrentUserLiked: !!userLike,
  };
}
```

#### Comment Operations

```typescript
async function createComment(
  userId: number,
  activityId: number,
  content: string
): Promise<ActivityComment> {
  // Validate content
  const trimmedContent = content.trim();
  if (!trimmedContent) {
    throw new Error("Comment content cannot be empty");
  }

  if (trimmedContent.length > 1000) {
    throw new Error("Comment content too long (max 1000 characters)");
  }

  // Check if activity exists and user can view it
  const hasReadPermission = await checkActivityPermission(
    userId,
    activityId,
    ActivityPermission.READ
  );
  if (!hasReadPermission) {
    throw new Error("Activity not found or access denied");
  }

  return await activityCommentRepository.create({
    userId,
    activityId,
    content: trimmedContent,
    createdAt: new Date(),
  });
}

async function updateComment(
  userId: number,
  commentId: number,
  content: string
): Promise<ActivityComment> {
  const comment = await activityCommentRepository.findById(commentId);
  if (!comment) {
    throw new Error("Comment not found");
  }

  if (comment.userId !== userId) {
    throw new Error("Not authorized to update this comment");
  }

  const trimmedContent = content.trim();
  if (!trimmedContent) {
    throw new Error("Comment content cannot be empty");
  }

  return await activityCommentRepository.update(commentId, {
    content: trimmedContent,
    updatedAt: new Date(),
  });
}

async function deleteComment(userId: number, commentId: number): Promise<void> {
  const comment = await activityCommentRepository.findById(commentId);
  if (!comment) {
    throw new Error("Comment not found");
  }

  if (comment.userId !== userId) {
    throw new Error("Not authorized to delete this comment");
  }

  await activityCommentRepository.delete(commentId);
}
```

### Data Validation & Sanitization

#### Input Sanitization

```typescript
import DOMPurify from "isomorphic-dompurify";

function sanitizeInput(input: string): string {
  return DOMPurify.sanitize(input.trim());
}

function validateEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

function validateActivityType(type: string): type is ActivityType {
  return Object.values(ActivityType).includes(type as ActivityType);
}

function validateDateRange(startDate: Date, endDate: Date): boolean {
  const start = new Date(startDate);
  const end = new Date(endDate);

  // End date must be after start date
  if (end <= start) return false;

  // Activity cannot be longer than 24 hours
  const maxDuration = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
  if (end.getTime() - start.getTime() > maxDuration) return false;

  // Activity cannot be in the future (with 5 minute tolerance)
  const now = new Date();
  const tolerance = 5 * 60 * 1000; // 5 minutes
  if (start.getTime() > now.getTime() + tolerance) return false;

  return true;
}
```

### Error Handling & Logging

#### Custom Error Classes

```typescript
export class ValidationError extends Error {
  constructor(message: string, public field?: string, public details?: any) {
    super(message);
    this.name = "ValidationError";
  }
}

export class AuthenticationError extends Error {
  constructor(message: string = "Authentication failed") {
    super(message);
    this.name = "AuthenticationError";
  }
}

export class AuthorizationError extends Error {
  constructor(message: string = "Access denied") {
    super(message);
    this.name = "AuthorizationError";
  }
}

export class NotFoundError extends Error {
  constructor(resource: string, id?: number | string) {
    super(`${resource}${id ? ` with id ${id}` : ""} not found`);
    this.name = "NotFoundError";
  }
}

export class ConflictError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConflictError";
  }
}
```

#### Logging Strategy

```typescript
import winston from "winston";

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || "info",
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: "logs/error.log", level: "error" }),
    new winston.transports.File({ filename: "logs/combined.log" }),
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      ),
    }),
  ],
});

// Request logging middleware
export function requestLogger(req: Request, res: Response, next: NextFunction) {
  const start = Date.now();

  res.on("finish", () => {
    const duration = Date.now() - start;
    logger.info({
      method: req.method,
      url: req.url,
      statusCode: res.statusCode,
      duration: `${duration}ms`,
      userAgent: req.get("User-Agent"),
      userId: req.user?.userId,
    });
  });

  next();
}
```

## 6. Error Handling

### Standard Error Responses

```typescript
interface ErrorResponse {
  error: string;
  message: string;
  statusCode: number;
  timestamp: string;
}
```

### Common Error Scenarios

- **401 Unauthorized**: Invalid/expired token
- **403 Forbidden**: Insufficient permissions
- **404 Not Found**: Resource doesn't exist
- **409 Conflict**: Duplicate data (username, friend request)
- **422 Validation Error**: Invalid input data
- **500 Internal Server Error**: Unexpected server errors

## 7. Security Requirements

### Password Security

- Minimum 8 characters
- Hash with bcrypt (salt rounds: 12)
- No password in API responses

### JWT Implementation

- Access tokens: 1 hour expiration
- Refresh tokens: 7 days expiration
- Include user ID and username in payload
- Sign with strong secret key

### File Upload Security

- Validate file types (images only)
- Size limits (10MB max)
- Sanitize file names
- Store securely (not in web-accessible directory)

### Database Security

- Use parameterized queries (ORM handles this)
- Connection pooling
- Environment variables for credentials

## 8. Performance Requirements

### Database Optimization

- Indexes on frequently queried fields (username, activity dates)
- Pagination for all list endpoints (default 10 items)
- Lazy loading for related entities
- Connection pooling (max 5 connections)

### Caching Strategy

- Consider Redis for session storage
- Cache frequently accessed user data
- Implement proper cache invalidation

### File Handling

- Efficient binary data storage
- Proper content-type headers for images
- Consider cloud storage for production

## 9. Development Guidelines

## 9. Development Guidelines - Complete Implementation Structure

### Project Structure

```
rythmrun-backend/
├── src/
│   ├── controllers/              # HTTP request handlers
│   │   ├── auth.controller.ts
│   │   ├── user.controller.ts
│   │   ├── activity.controller.ts
│   │   ├── comment.controller.ts
│   │   └── friend.controller.ts
│   ├── services/                 # Business logic layer
│   │   ├── auth.service.ts
│   │   ├── user.service.ts
│   │   ├── activity.service.ts
│   │   ├── comment.service.ts
│   │   ├── friend.service.ts
│   │   └── email.service.ts
│   ├── repositories/             # Data access layer
│   │   ├── user.repository.ts
│   │   ├── activity.repository.ts
│   │   ├── location.repository.ts
│   │   ├── comment.repository.ts
│   │   ├── like.repository.ts
│   │   ├── friend-request.repository.ts
│   │   └── refresh-token.repository.ts
│   ├── models/                   # Entity definitions & DTOs
│   │   ├── entities/
│   │   │   ├── user.entity.ts
│   │   │   ├── activity.entity.ts
│   │   │   ├── location.entity.ts
│   │   │   ├── activity-comment.entity.ts
│   │   │   ├── activity-like.entity.ts
│   │   │   ├── friend-request.entity.ts
│   │   │   └── refresh-token.entity.ts
│   │   ├── dtos/
│   │   │   ├── auth.dto.ts
│   │   │   ├── user.dto.ts
│   │   │   ├── activity.dto.ts
│   │   │   ├── comment.dto.ts
│   │   │   └── friend.dto.ts
│   │   └── enums/
│   │       ├── activity-type.enum.ts
│   │       └── friend-request-status.enum.ts
│   ├── middleware/               # Request processing middleware
│   │   ├── auth.middleware.ts
│   │   ├── validation.middleware.ts
│   │   ├── error.middleware.ts
│   │   ├── cors.middleware.ts
│   │   ├── rate-limit.middleware.ts
│   │   └── file-upload.middleware.ts
│   ├── routes/                   # Route definitions
│   │   ├── auth.routes.ts
│   │   ├── user.routes.ts
│   │   ├── activity.routes.ts
│   │   ├── comment.routes.ts
│   │   ├── friend.routes.ts
│   │   └── index.ts
│   ├── utils/                    # Helper functions
│   │   ├── jwt.util.ts
│   │   ├── password.util.ts
│   │   ├── distance.util.ts
│   │   ├── validation.util.ts
│   │   ├── file.util.ts
│   │   └── logger.util.ts
│   ├── config/                   # Configuration files
│   │   ├── database.config.ts
│   │   ├── jwt.config.ts
│   │   ├── email.config.ts
│   │   ├── upload.config.ts
│   │   └── app.config.ts
│   ├── database/                 # Database setup
│   │   ├── migrations/
│   │   ├── seeds/
│   │   └── connection.ts
│   ├── types/                    # TypeScript type definitions
│   │   ├── express.d.ts
│   │   ├── jwt.d.ts
│   │   └── custom.d.ts
│   └── app.ts                    # Express app setup
├── tests/                        # Test files
│   ├── unit/
│   │   ├── services/
│   │   ├── repositories/
│   │   └── utils/
│   ├── integration/
│   │   ├── auth/
│   │   ├── user/
│   │   ├── activity/
│   │   └── friend/
│   ├── fixtures/
│   │   ├── users.json
│   │   ├── activities.json
│   │   └── locations.json
│   └── setup/
│       ├── test-db.ts
│       └── test-helpers.ts
├── docs/                         # API documentation
│   ├── swagger.yaml
│   ├── postman-collection.json
│   └── README.md
├── logs/                         # Log files
├── uploads/                      # File uploads (dev only)
├── scripts/                      # Utility scripts
│   ├── setup-db.ts
│   ├── seed-data.ts
│   └── cleanup-tokens.ts
├── .env.example                  # Environment template
├── .gitignore
├── .eslintrc.js
├── .prettierrc
├── jest.config.js
├── tsconfig.json
├── package.json
├── Dockerfile
└── README.md
```

### Core Files Implementation

#### Entry Point (`src/app.ts`)

```typescript
import express from "express";
import cors from "cors";
import helmet from "helmet";
import compression from "compression";
import rateLimit from "express-rate-limit";
import { errorHandler } from "./middleware/error.middleware";
import { requestLogger } from "./utils/logger.util";
import routes from "./routes";
import { connectDatabase } from "./database/connection";

const app = express();

// Security middleware
app.use(helmet());
app.use(
  cors({
    origin: process.env.FRONTEND_URL || "http://localhost:3000",
    credentials: true,
  })
);

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: "Too many requests from this IP",
});
app.use("/api/", limiter);

// Body parsing
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));
app.use(compression());

// Logging
app.use(requestLogger);

// Health check
app.get("/health", (req, res) => {
  res.json({ status: "OK", timestamp: new Date().toISOString() });
});

// API routes
app.use("/api", routes);

// Error handling
app.use(errorHandler);

// 404 handler
app.use("*", (req, res) => {
  res.status(404).json({
    error: "NOT_FOUND",
    message: "Endpoint not found",
    statusCode: 404,
  });
});

// Start server
const PORT = process.env.PORT || 8080;

async function startServer() {
  try {
    await connectDatabase();
    app.listen(PORT, () => {
      console.log(`🚀 Server running on port ${PORT}`);
    });
  } catch (error) {
    console.error("Failed to start server:", error);
    process.exit(1);
  }
}

startServer();

export default app;
```

#### Database Connection (`src/database/connection.ts`)

```typescript
import { DataSource } from "typeorm";
import { User } from "../models/entities/user.entity";
import { Activity } from "../models/entities/activity.entity";
import { Location } from "../models/entities/location.entity";
import { ActivityComment } from "../models/entities/activity-comment.entity";
import { ActivityLike } from "../models/entities/activity-like.entity";
import { FriendRequest } from "../models/entities/friend-request.entity";
import { RefreshToken } from "../models/entities/refresh-token.entity";

export const AppDataSource = new DataSource({
  type: "postgres",
  host: process.env.DB_HOST || "localhost",
  port: parseInt(process.env.DB_PORT || "5432"),
  username: process.env.DB_USERNAME || "postgres",
  password: process.env.DB_PASSWORD || "postgres",
  database: process.env.DB_NAME || "rythmrundb",
  schema: process.env.DB_SCHEMA || "rythmrundb",
  synchronize: process.env.NODE_ENV === "development",
  logging: process.env.NODE_ENV === "development",
  entities: [
    User,
    Activity,
    Location,
    ActivityComment,
    ActivityLike,
    FriendRequest,
    RefreshToken,
  ],
  migrations: ["src/database/migrations/*.ts"],
  subscribers: ["src/database/subscribers/*.ts"],
});

export async function connectDatabase(): Promise<void> {
  try {
    await AppDataSource.initialize();
    console.log("✅ Database connected successfully");
  } catch (error) {
    console.error("❌ Database connection failed:", error);
    throw error;
  }
}
```

#### Main Routes (`src/routes/index.ts`)

```typescript
import { Router } from "express";
import authRoutes from "./auth.routes";
import userRoutes from "./user.routes";
import activityRoutes from "./activity.routes";
import friendRoutes from "./friend.routes";

const router = Router();

// Public routes
router.use("/user", authRoutes);

// Protected routes
router.use("/private/user", userRoutes);
router.use("/private/activity", activityRoutes);
router.use("/private/friends", friendRoutes);

export default router;
```

#### Authentication Middleware (`src/middleware/auth.middleware.ts`)

```typescript
import { Request, Response, NextFunction } from "express";
import { verifyAccessToken } from "../utils/jwt.util";
import { AuthenticationError } from "../utils/errors";

export interface AuthenticatedRequest extends Request {
  user: {
    userId: number;
    username: string;
  };
}

export function authenticateToken(
  req: Request,
  res: Response,
  next: NextFunction
) {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) {
    return res.status(401).json({
      error: "UNAUTHORIZED",
      message: "Access token required",
      statusCode: 401,
      timestamp: new Date().toISOString(),
    });
  }

  try {
    const decoded = verifyAccessToken(token);
    (req as AuthenticatedRequest).user = {
      userId: decoded.userId,
      username: decoded.username,
    };
    next();
  } catch (error) {
    return res.status(401).json({
      error: "UNAUTHORIZED",
      message: "Invalid or expired token",
      statusCode: 401,
      timestamp: new Date().toISOString(),
    });
  }
}
```

#### Validation Middleware (`src/middleware/validation.middleware.ts`)

```typescript
import { Request, Response, NextFunction } from "express";
import { ObjectSchema } from "joi";

export function validateBody(schema: ObjectSchema) {
  return (req: Request, res: Response, next: NextFunction) => {
    const { error, value } = schema.validate(req.body);

    if (error) {
      return res.status(422).json({
        error: "VALIDATION_ERROR",
        message: "Validation failed",
        statusCode: 422,
        details: error.details.map((detail) => ({
          field: detail.path.join("."),
          message: detail.message,
        })),
        timestamp: new Date().toISOString(),
      });
    }

    req.body = value;
    next();
  };
}

export function validateQuery(schema: ObjectSchema) {
  return (req: Request, res: Response, next: NextFunction) => {
    const { error, value } = schema.validate(req.query);

    if (error) {
      return res.status(422).json({
        error: "VALIDATION_ERROR",
        message: "Query validation failed",
        statusCode: 422,
        details: error.details.map((detail) => ({
          field: detail.path.join("."),
          message: detail.message,
        })),
        timestamp: new Date().toISOString(),
      });
    }

    req.query = value;
    next();
  };
}
```

#### Error Handling Middleware (`src/middleware/error.middleware.ts`)

```typescript
import { Request, Response, NextFunction } from "express";
import { logger } from "../utils/logger.util";

export function errorHandler(
  error: Error,
  req: Request,
  res: Response,
  next: NextFunction
) {
  logger.error({
    error: error.message,
    stack: error.stack,
    url: req.url,
    method: req.method,
    userId: (req as any).user?.userId,
  });

  // Handle specific error types
  if (error.name === "ValidationError") {
    return res.status(422).json({
      error: "VALIDATION_ERROR",
      message: error.message,
      statusCode: 422,
      timestamp: new Date().toISOString(),
    });
  }

  if (error.name === "AuthenticationError") {
    return res.status(401).json({
      error: "UNAUTHORIZED",
      message: error.message,
      statusCode: 401,
      timestamp: new Date().toISOString(),
    });
  }

  if (error.name === "AuthorizationError") {
    return res.status(403).json({
      error: "FORBIDDEN",
      message: error.message,
      statusCode: 403,
      timestamp: new Date().toISOString(),
    });
  }

  if (error.name === "NotFoundError") {
    return res.status(404).json({
      error: "NOT_FOUND",
      message: error.message,
      statusCode: 404,
      timestamp: new Date().toISOString(),
    });
  }

  if (error.name === "ConflictError") {
    return res.status(409).json({
      error: "CONFLICT",
      message: error.message,
      statusCode: 409,
      timestamp: new Date().toISOString(),
    });
  }

  // Generic server error
  res.status(500).json({
    error: "INTERNAL_SERVER_ERROR",
    message: "An unexpected error occurred",
    statusCode: 500,
    timestamp: new Date().toISOString(),
  });
}
```

### Environment Configuration

#### Environment Variables (`.env.example`)

```env
# Application
NODE_ENV=development
PORT=8080
FRONTEND_URL=http://localhost:3000

# Database
DB_HOST=localhost
DB_PORT=5432
DB_USERNAME=postgres
DB_PASSWORD=postgres
DB_NAME=rythmrundb
DB_SCHEMA=rythmrundb

# JWT Configuration
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production
JWT_EXPIRES_IN=1h
REFRESH_TOKEN_SECRET=your-super-secret-refresh-token-key
REFRESH_TOKEN_EXPIRES_IN=7d

# Email Configuration (Gmail SMTP)
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USERNAME=your-email@gmail.com
EMAIL_PASSWORD=your-app-password
EMAIL_FROM=noreply@rythmrun.com

# File Upload
UPLOAD_FOLDER=./uploads
MAX_FILE_SIZE=10485760

# Logging
LOG_LEVEL=info
LOG_FILE_PATH=./logs

# Security
BCRYPT_SALT_ROUNDS=12
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# External APIs (if needed)
MAPS_API_KEY=your-google-maps-api-key
```

#### TypeScript Configuration (`tsconfig.json`)

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "allowSyntheticDefaultImports": true,
    "baseUrl": "./src",
    "paths": {
      "@/*": ["*"],
      "@/controllers/*": ["controllers/*"],
      "@/services/*": ["services/*"],
      "@/repositories/*": ["repositories/*"],
      "@/models/*": ["models/*"],
      "@/middleware/*": ["middleware/*"],
      "@/utils/*": ["utils/*"],
      "@/config/*": ["config/*"]
    }
  },
  "include": ["src/**/*", "tests/**/*"],
  "exclude": ["node_modules", "dist", "logs"]
}
```

#### Package.json Scripts

```json
{
  "name": "rythmrun-backend",
  "version": "1.0.0",
  "description": "RythmRun fitness tracking API built with Node.js",
  "main": "dist/app.js",
  "scripts": {
    "dev": "nodemon src/app.ts",
    "build": "tsc",
    "start": "node dist/app.js",
    "test": "jest",
    "test:watch": "jest --watch",
    "test:coverage": "jest --coverage",
    "test:e2e": "jest --config ./tests/jest-e2e.json",
    "lint": "eslint src/**/*.ts",
    "lint:fix": "eslint src/**/*.ts --fix",
    "format": "prettier --write src/**/*.ts",
    "typeorm": "typeorm-ts-node-commonjs",
    "migration:generate": "npm run typeorm -- migration:generate src/database/migrations/migration -d src/database/connection.ts",
    "migration:run": "npm run typeorm -- migration:run -d src/database/connection.ts",
    "migration:revert": "npm run typeorm -- migration:revert -d src/database/connection.ts",
    "seed": "ts-node scripts/seed-data.ts",
    "cleanup-tokens": "ts-node scripts/cleanup-tokens.ts"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.0.0",
    "compression": "^1.7.4",
    "express-rate-limit": "^6.7.0",
    "typeorm": "^0.3.16",
    "pg": "^8.11.0",
    "bcrypt": "^5.1.0",
    "jsonwebtoken": "^9.0.0",
    "joi": "^17.9.2",
    "multer": "^1.4.5-lts.1",
    "nodemailer": "^6.9.3",
    "winston": "^3.9.0",
    "dotenv": "^16.1.4",
    "class-transformer": "^0.5.1",
    "class-validator": "^0.14.0",
    "reflect-metadata": "^0.1.13"
  },
  "devDependencies": {
    "@types/express": "^4.17.17",
    "@types/cors": "^2.8.13",
    "@types/compression": "^1.7.2",
    "@types/bcrypt": "^5.0.0",
    "@types/jsonwebtoken": "^9.0.2",
    "@types/multer": "^1.4.7",
    "@types/nodemailer": "^6.4.8",
    "@types/node": "^20.3.1",
    "@types/jest": "^29.5.2",
    "@types/supertest": "^2.0.12",
    "typescript": "^5.1.3",
    "ts-node": "^10.9.1",
    "nodemon": "^2.0.22",
    "jest": "^29.5.0",
    "ts-jest": "^29.1.0",
    "supertest": "^6.3.3",
    "eslint": "^8.43.0",
    "@typescript-eslint/eslint-plugin": "^5.59.11",
    "@typescript-eslint/parser": "^5.59.11",
    "prettier": "^2.8.8"
  }
}
```

### Testing Configuration

#### Jest Configuration (`jest.config.js`)

```javascript
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/src", "<rootDir>/tests"],
  testMatch: ["**/__tests__/**/*.ts", "**/?(*.)+(spec|test).ts"],
  transform: {
    "^.+\\.ts$": "ts-jest",
  },
  collectCoverageFrom: [
    "src/**/*.ts",
    "!src/**/*.d.ts",
    "!src/app.ts",
    "!src/database/migrations/**",
    "!src/database/seeds/**",
  ],
  coverageDirectory: "coverage",
  coverageReporters: ["text", "lcov", "html"],
  setupFilesAfterEnv: ["<rootDir>/tests/setup/test-helpers.ts"],
  testTimeout: 10000,
};
```

#### Test Database Setup (`tests/setup/test-db.ts`)

```typescript
import { DataSource } from "typeorm";
import { AppDataSource } from "../../src/database/connection";

export const testDataSource = new DataSource({
  ...AppDataSource.options,
  database: process.env.TEST_DB_NAME || "rythmrundb_test",
  synchronize: true,
  dropSchema: true,
  logging: false,
});

export async function setupTestDatabase() {
  await testDataSource.initialize();
}

export async function teardownTestDatabase() {
  await testDataSource.destroy();
}

export async function clearDatabase() {
  const entities = testDataSource.entityMetadatas;
  for (const entity of entities) {
    const repository = testDataSource.getRepository(entity.name);
    await repository.clear();
  }
}
```

## 10. Deployment Considerations

### Production Setup

- Use PM2 for process management
- Environment-specific configurations
- Database migrations
- Logging with Winston
- Health check endpoints
- CORS configuration for frontend

### Monitoring

- Request/response logging
- Error tracking
- Performance metrics
- Database query monitoring

## 11. Migration Plan

### Phase 1: Core Setup

1. Project initialization with TypeScript/Express
2. Database setup with Prisma/TypeORM
3. Basic authentication (JWT)
4. User management endpoints

### Phase 2: Activity Features

1. Activity CRUD operations
2. Location tracking
3. Activity calculations
4. File upload for profile pictures

### Phase 3: Social Features

1. Friend request system
2. Activity comments and likes
3. Activity feed (mine + friends)

### Phase 4: Additional Features

1. Email functionality
2. API documentation
3. Testing coverage
4. Performance optimization

## 12. Learning Objectives

By building this Node.js backend, you'll learn:

- **Modern Node.js** development with TypeScript
- **RESTful API** design and implementation
- **Database** design and ORM usage
- **Authentication** and authorization patterns
- **File handling** and binary data management
- **Error handling** and validation strategies
- **Testing** methodologies for APIs
- **Security** best practices
- **Performance** optimization techniques
- **Clean architecture** principles

This comprehensive rebuild will provide hands-on experience with modern backend development while maintaining compatibility with the existing Flutter frontend.

## 13. Implementation Checklist

### Setup Phase ✓

- [ ] Initialize Node.js project with TypeScript
- [ ] Install and configure dependencies (Express, Prisma/TypeORM, JWT, etc.)
- [ ] Set up database connection and migrations
- [ ] Configure environment variables
- [ ] Set up basic project structure

### Authentication System ✓

- [ ] Implement user registration endpoint
- [ ] Implement login endpoint with JWT generation
- [ ] Create JWT middleware for protected routes
- [ ] Implement password reset flow
- [ ] Add user profile management
- [ ] Set up password hashing with bcrypt

### Activity Management ✓

- [ ] Create Activity entity and database schema
- [ ] Implement activity CRUD operations
- [ ] Add activity validation and calculations
- [ ] Implement activity search and filtering
- [ ] Add activity statistics endpoints

### Social Features ✓

- [ ] Implement friend request system
- [ ] Create activity likes and comments
- [ ] Build activity feed (personal + friends)
- [ ] Add privacy controls

### File Handling ✓

- [ ] Set up multer for file uploads
- [ ] Implement profile picture upload
- [ ] Add image validation and processing
- [ ] Configure file storage (local/cloud)

### Testing & Documentation ✓

- [ ] Write unit tests for all services
- [ ] Create integration tests for API endpoints
- [ ] Add Swagger/OpenAPI documentation
- [ ] Set up test database

### Deployment ✓

- [ ] Configure production environment
- [ ] Set up logging and monitoring
- [ ] Add health check endpoints
- [ ] Configure CORS for frontend
- [ ] Set up database backup strategy

## 14. Quick Start Commands

Once you start implementing, here are the key commands you'll use:

```bash
# Project setup
npm init -y
npm install express typescript prisma @types/node @types/express
npm install -D nodemon ts-node @types/jest jest

# Database operations
npx prisma init
npx prisma migrate dev --name init
npx prisma generate
npx prisma studio

# Development
npm run dev          # Start development server
npm run build        # Compile TypeScript
npm run test         # Run tests
npm run test:watch   # Run tests in watch mode

# Database reset (development only)
npx prisma migrate reset
```

## 15. Common Patterns You'll Implement

### Repository Pattern

```typescript
// Base repository interface
interface IRepository<T> {
  findById(id: number): Promise<T | null>;
  findAll(): Promise<T[]>;
  create(data: Partial<T>): Promise<T>;
  update(id: number, data: Partial<T>): Promise<T>;
  delete(id: number): Promise<void>;
}

// User repository implementation
class UserRepository implements IRepository<User> {
  // Implementation using Prisma/TypeORM
}
```

### Service Layer Pattern

```typescript
// Service handling business logic
class UserService {
  constructor(private userRepository: UserRepository) {}

  async createUser(userData: CreateUserDto): Promise<User> {
    // Validation, business logic, repository calls
  }
}
```

### Controller Pattern

```typescript
// Controller handling HTTP requests/responses
class UserController {
  constructor(private userService: UserService) {}

  async createUser(req: Request, res: Response): Promise<void> {
    // Request validation, service calls, response formatting
  }
}
```

### Middleware Pattern

```typescript
// Authentication middleware
const authenticateToken = (req: Request, res: Response, next: NextFunction) => {
  // JWT validation logic
};

// Validation middleware
const validateCreateUser = (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  // Input validation logic
};
```

This comprehensive requirements document provides everything needed to implement the RythmRun Node.js backend. Each section builds upon the previous one, creating a complete roadmap from setup to deployment.

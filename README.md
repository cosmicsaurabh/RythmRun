# RythmRun 🏃‍♂️

[![TypeScript](https://img.shields.io/badge/TypeScript-007ACC?style=for-the-badge&logo=typescript&logoColor=white)](https://typescriptlang.org/)
[![Node.js](https://img.shields.io/badge/Node.js-43853D?style=for-the-badge&logo=node.js&logoColor=white)](https://nodejs.org/)
[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)](https://postgresql.org/)
[![Prisma](https://img.shields.io/badge/Prisma-3982CE?style=for-the-badge&logo=Prisma&logoColor=white)](https://prisma.io/)

A comprehensive fitness tracking application that combines the power of rhythm and running. RythmRun helps users track their fitness activities, connect with friends, and stay motivated through social features and real-time GPS tracking.

## 📱 Current Version

- **Version**: 1.0.0+16
- **Bundle ID**: `com.github.cosmicsaurabh.rythmrun`
- **Play Store**: [RythmRun on Google Play](https://play.google.com/store/apps/details?id=com.github.cosmicsaurabh.rythmrun)

## 🎯 Features

### Core Features

- **Live GPS Tracking**: Real-time location tracking during workouts with map visualization
- **Activity Tracking**: Log runs, walks, cycling with detailed metrics (distance, duration, pace, calories)
- **Social Features**: Friend system, activity feeds, likes, and comments
- **Profile Management**: Avatar uploads with AWS S3 cloud storage and CloudFront CDN
- **Offline Support**: Local SQLite database for offline tracking and data persistence

### Monetization

- **AdMob Integration**: Banner ads, interstitial ads, and rewarded video ads
- **Start-of-Day Offer**: Watch a rewarded ad for ad-free experience throughout the day
- **Non-intrusive Ads**: Banner ads on track screen, interstitial after completing activities

### Technical Features

- **JWT Authentication**: Secure token-based auth with automatic refresh
- **Multi-Environment Config**: Dev, staging, and production configurations
- **Clean Architecture**: Domain-driven design with Repository pattern
- **State Management**: Riverpod for reactive state management

## 🏗️ Architecture

### Backend (Node.js + TypeScript)

```
RythmRun_backend_nodejs/
├── src/
│   ├── controllers/          # API request handlers
│   │   ├── user.controller.ts
│   │   ├── activity.controller.ts
│   │   ├── avatar.controller.ts
│   │   ├── friend.controller.ts
│   │   ├── like.controller.ts
│   │   └── comment.controller.ts
│   ├── services/             # Business logic
│   ├── routes/               # API route definitions
│   ├── middleware/           # Auth, validation middleware
│   ├── models/               # DTOs and types
│   ├── config/               # DI container, config
│   └── utils/                # Utilities
├── prisma/
│   ├── schema.prisma         # Database schema
│   └── migrations/           # Database migrations
└── uploads/                  # Local file storage (legacy)
```

**Tech Stack:**

- Express.js with TypeScript
- PostgreSQL with Prisma ORM
- TSyringe for Dependency Injection
- JWT + bcrypt for authentication
- AWS S3 for file storage
- CloudFront CDN for image delivery
- Winston for logging
- Joi + class-validator for validation

### Frontend (Flutter)

```
rythmrun_frontend_flutter/
├── lib/
│   ├── main.dart             # App entry point
│   ├── core/                 # Core utilities, config, services
│   │   ├── config/           # App configuration (URLs, environments)
│   │   └── services/         # Core services (settings, tracking)
│   ├── data/                 # Data layer
│   │   ├── datasources/      # Remote & local data sources
│   │   └── repositories/     # Repository implementations
│   ├── domain/               # Domain layer
│   │   ├── entities/         # Business entities
│   │   └── repositories/     # Repository interfaces
│   ├── presentation/         # UI layer
│   │   ├── features/         # Feature screens
│   │   │   ├── home/         # Main navigation
│   │   │   ├── live_tracking/# GPS tracking screen
│   │   │   ├── tracking_history/# Past activities
│   │   │   ├── profile/      # User profile
│   │   │   ├── settings/     # App settings
│   │   │   ├── login/        # Authentication
│   │   │   ├── registration/ # User registration
│   │   │   └── Map/          # Map components
│   │   └── common/           # Shared providers
│   ├── features/             # Feature modules
│   │   └── ads/              # AdMob integration
│   │       ├── core/         # Ads config, placement, result types
│   │       ├── providers/    # AdMob & NoOp providers
│   │       ├── presentation/ # Ad widgets
│   │       └── service/      # Ads service & storage
│   └── theme/                # App theming
├── assets/                   # Fonts, images
└── android/                  # Android platform code
```

**Tech Stack:**

- Flutter 3.7+ with Dart
- Riverpod for state management
- flutter_map for offline maps
- Geolocator for GPS tracking
- flutter_secure_storage for tokens
- sqflite for local database
- google_mobile_ads for monetization
- http package for API calls

## 🚀 Deployment

### Backend

- **Hosting**: Render (https://rythmrun.onrender.com)
- **Database**: Railway PostgreSQL
- **CDN**: AWS CloudFront (d2ixgo5od14vvq.cloudfront.net)
- **File Storage**: AWS S3

### Frontend

- **Android**: Google Play Store
- **Bundle ID**: `com.github.cosmicsaurabh.rythmrun`

## 📊 Database Schema

```prisma
model User {
  id, firstname, lastname, username, password
  profilePicturePath, profilePictureType
  activities[], comments[], likes[], friends[]
  refreshToken
}

model Activity {
  id, userId, type, startTime, endTime
  distance, duration, avgSpeed, maxSpeed, calories
  description, isPublic
  locations[], comments[], likes[]
}

model Location {
  id, activityId, latitude, longitude, altitude
  timestamp, accuracy, speed
}

model Friend {
  id, user1Id, user2Id, status (pending/accepted)
}

model Comment { id, activityId, userId, content }
model Like { id, activityId, userId }
model RefreshToken { id, userId, token, expiryDate }
```

## 🔗 API Endpoints

### Authentication

```http
POST /api/users/register      # Register new user
POST /api/users/login         # Login (returns JWT tokens)
POST /api/users/logout        # Logout (invalidate refresh token)
POST /api/users/refresh-token # Refresh access token
PUT  /api/users/change-password # Change password
```

### Profile & Avatar

```http
GET  /api/users/profile       # Get user profile
PUT  /api/users/profile       # Update profile
POST /api/avatar/upload-url   # Get presigned S3 URL
POST /api/avatar/confirm      # Confirm avatar upload
```

### Activities

```http
GET    /api/activities              # Get activities (paginated)
GET    /api/activities/:id          # Get activity details
POST   /api/activities              # Create activity
PATCH  /api/activities/:id          # Update activity
DELETE /api/activities/:id          # Delete activity
```

### Social

```http
POST   /api/friends/requests              # Send friend request
GET    /api/friends/requests/pending      # Get pending requests
POST   /api/friends/requests/:id/accept   # Accept request
POST   /api/friends/requests/:id/reject   # Reject request
GET    /api/friends/status/:userId        # Check friendship status

GET    /api/activities/:id/likes          # Get like status
POST   /api/activities/:id/likes          # Like activity
DELETE /api/activities/:id/likes          # Unlike activity

GET    /api/activities/:id/comments       # Get comments
POST   /api/activities/:id/comments       # Add comment
PATCH  /api/activities/:id/comments/:cid  # Edit comment
DELETE /api/activities/:id/comments/:cid  # Delete comment
```

## 🛠️ Development Setup

### Prerequisites

- Node.js 22.x (the backend package and CI use this supported runtime line)
- Flutter SDK 3.7+
- PostgreSQL 14+
- Android Studio / Xcode

### Backend Setup

```bash
cd RythmRun_backend_nodejs
npm install --no-audit

# Configure environment
cp .env.example .env
# Edit .env with your credentials

# Database setup
npx prisma migrate dev
npx prisma generate

# Run development server
npm run dev
```

### Frontend Setup

```bash
cd rythmrun_frontend_flutter
flutter pub get

# Update API URL in lib/core/config/app_config.dart if needed
# Run the app
flutter run
```

### Environment Variables (Backend)

```env
DATABASE_URL="postgresql://user:pass@host:5432/db"
JWT_SECRET="your-jwt-secret"
JWT_REFRESH_SECRET="your-refresh-secret"
PORT=8080

# AWS S3
AWS_REGION="your-region"
AWS_ACCESS_KEY_ID="your-key"
AWS_SECRET_ACCESS_KEY="your-secret"
S3_BUCKET_NAME="your-bucket"
CLOUDFRONT_DOMAIN="your-cloudfront.cloudfront.net"
```

## 📱 App Screens

| Screen       | Description                                    |
| ------------ | ---------------------------------------------- |
| Landing      | App intro with login/register options          |
| Registration | User signup with validation                    |
| Login        | User authentication                            |
| Home         | Bottom navigation (Track, Activities, Profile) |
| Track        | Live GPS tracking with map                     |
| Activities   | Past workout history                           |
| Profile      | User info, avatar, settings                    |
| Settings     | Theme, logout, account management              |

## 💰 Monetization (AdMob)

### Ad Placements

- **Start-of-Day Offer**: Rewarded video ad - watch once for ad-free day
- **Post-Activity Ad**: Interstitial ad after completing a workout
- **Banner Ad**: Banner at bottom of Track screen

### Ad Unit IDs

- App ID: `ca-app-pub-9575153117176686~2854069054`
- Publisher verification: [app-ads.txt](https://cosmicsaurabh.github.io/RythmRun/app-ads.txt)

## 📄 Documentation

- [Privacy Policy](https://cosmicsaurabh.github.io/RythmRun/privacy-policy)
- [Terms of Service](https://cosmicsaurabh.github.io/RythmRun/terms)
- [Delete Account](https://cosmicsaurabh.github.io/RythmRun/delete-account)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the ISC License.

---

**RythmRun** - Where rhythm meets running! 🎵🏃‍♂️

Built with ❤️ by [@cosmicsaurabh](https://github.com/cosmicsaurabh)

# RythmRun 🏃‍♂️

A comprehensive fitness tracking application that combines the power of rhythm and running. RythmRun helps users track their fitness activities, connect with friends, and stay motivated through social features and real-time tracking.

## 🏗️ Project Architecture

RythmRun is built as a full-stack application with:

- **Frontend**: Flutter mobile app with clean architecture
- **Backend**: Node.js/Express API with TypeScript
- **Database**: PostgreSQL with Prisma ORM
- **Authentication**: JWT-based authentication system

## 📱 Features

### 🎯 Latest Features (v1.0.0+7)
- ✨ **Avatar Upload System**: Complete avatar/profile picture upload with AWS S3 cloud storage integration
- 🖼️ **Enhanced Profile Screen**: Redesigned profile interface with improved UI/UX
- ☁️ **Cloud Storage**: Secure, scalable image storage using AWS S3 with CloudFront CDN
- 📸 **Image Picker**: Easy-to-use image selection from device gallery
- 🔄 **Token Refresh**: Automatic token refresh mechanism for seamless authentication
- 🌐 **Production Deployment**: Backend deployed on Railway with production environment support
- 📱 **Multi-Environment Support**: Dev, staging, and production configurations

### Core Features
- **User Authentication**: Secure registration, login, logout, and token refresh system
- **Profile Management**: Complete user profiles with avatar uploads, profile editing, and password change
- **Activity Tracking**: Create, view, update, and delete fitness activities with detailed statistics
- **Live GPS Tracking**: Real-time location tracking during workouts with map visualization
- **Social Features**: 
  - Friend requests (send, accept, reject, cancel)
  - Like/unlike activities
  - Comment on activities (create, read, update, delete)
  - View friendship status
- **Tracking History**: View past activities with detailed statistics and map visualization
- **Settings**: App configuration, theme preferences, and account management

### Technical Features
- **Offline Capability**: Local SQLite database for offline tracking and data persistence
- **Session Management**: Robust session handling with offline mode support
- **Real-time Location**: GPS tracking with geolocator and permission handling
- **Maps Integration**: Offline map support with flutter_map for visual tracking
- **Secure Storage**: Encrypted local storage for sensitive data (tokens, user info)
- **CDN Integration**: CloudFront CDN for fast avatar image delivery
- **Environment-aware Configuration**: Automatic dev/prod environment detection

## 🚀 Getting Started

### Prerequisites

- Node.js (v18 or higher)
- Flutter SDK (v3.7.0 or higher)
- PostgreSQL database
- Android Studio / Xcode (for mobile development)
- Git

### Backend Setup

1. **Navigate to backend directory**
   ```bash
   cd RythmRun_backend_nodejs
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   Create a `.env` file in the backend directory:
   ```env
   DATABASE_URL="postgresql://USER:PASSWORD@HOST:PORT/DATABASE"
   JWT_SECRET="your-secret-key-min-32-chars"
   JWT_REFRESH_SECRET="your-refresh-secret-min-32-chars"
   PORT=8080
   NODE_ENV=development
   
   # AWS S3 Configuration (for avatar uploads)
   AWS_REGION="your-aws-region"
   AWS_ACCESS_KEY_ID="your-access-key"
   AWS_SECRET_ACCESS_KEY="your-secret-key"
   S3_BUCKET_NAME="your-bucket-name"
   
   # CloudFront CDN (optional but recommended)
   CLOUDFRONT_DOMAIN="your-cloudfront-domain.cloudfront.net"
   ```

4. **Run database migrations**
   ```bash
   npx prisma migrate dev
   npx prisma generate
   ```

5. **Start the development server**
   ```bash
   npm run dev
   ```

   The API will be running on `http://localhost:8080` (or the port specified in .env)

### Frontend Setup

1. **Navigate to frontend directory**
   ```bash
   cd rythmrun_frontend_flutter
   ```

2. **Install Flutter dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure backend URL**
   The app uses environment-aware configuration in `lib/core/config/app_config.dart`:
   - **Development**: Automatically uses dev environment (`http://YOUR_LOCAL_IP:8080/api`)
   - **Production**: Automatically uses production URL (`--`)
   
   For local development, update the dev URL in `app_config.dart`:
   ```dart
   static const Map<String, String> _baseUrls = {
     'dev': 'http://YOUR_LOCAL_IP:8080/api', // Update with your local IP
     'prod': '--',
   };
   ```
   
   The app automatically detects debug/release mode and uses the appropriate environment.

4. **Run the app**
   ```bash
   flutter run
   ```

## 🛠️ Technology Stack

### Backend
- **Runtime**: Node.js
- **Framework**: Express.js
- **Language**: TypeScript
- **Database**: PostgreSQL
- **ORM**: Prisma
- **Authentication**: JWT (JSON Web Tokens)
- **Password Hashing**: bcrypt
- **File Uploads**: Multer & AWS S3
- **Cloud Storage**: AWS S3 for profile pictures and media
- **Validation**: Joi & class-validator
- **Logging**: Winston
- **Security**: Helmet, CORS

### Frontend
- **Framework**: Flutter
- **Language**: Dart
- **State Management**: Riverpod (with code generation)
- **HTTP Client**: http package
- **Local Database**: SQLite (sqflite)
- **Maps**: flutter_map (offline map support)
- **GPS Tracking**: Geolocator
- **Secure Storage**: Flutter Secure Storage
- **Permissions**: Permission Handler
- **Authentication**: JWT Decoder
- **Image Picker**: Image picker for profile pictures
- **Architecture**: Clean Architecture (Domain, Data, Presentation layers)
- **Theme**: Custom theme with light/dark mode support

## 📂 Project Structure

### Backend Structure
```
RythmRun_backend_nodejs/
├── src/
│   ├── controllers/     # API request handlers
│   │   ├── user.controller.ts
│   │   ├── activity.controller.ts
│   │   ├── avatar.controller.ts
│   │   ├── friend.controller.ts
│   │   ├── like.controller.ts
│   │   └── comment.controller.ts
│   ├── services/        # Business logic layer
│   │   ├── user.service.ts
│   │   ├── activity.service.ts
│   │   ├── s3.service.ts
│   │   └── ...
│   ├── routes/          # API endpoint definitions
│   │   ├── user.routes.ts
│   │   ├── activity.routes.ts
│   │   ├── avatar.routes.ts
│   │   ├── friend.routes.ts
│   │   ├── like.routes.ts
│   │   └── comment.routes.ts
│   ├── middleware/      # Authentication & validation
│   │   ├── auth.middleware.ts
│   │   ├── validation.middleware.ts
│   │   └── file-upload.middleware.ts
│   ├── models/          # DTOs and type definitions
│   ├── config/          # Application configuration & DI container
│   └── utils/           # Utility functions
├── prisma/              # Database schema and migrations
│   ├── schema.prisma
│   └── migrations/
├── uploads/             # File upload directory (local storage - legacy)
└── dist/               # Compiled JavaScript
```

### Frontend Structure
```
rythmrun_frontend_flutter/
├── lib/
│   ├── core/            # Core functionality (config, networking, DI)
│   ├── data/            # Data layer (repositories, datasources)
│   ├── domain/          # Domain layer (entities, use cases, repositories)
│   ├── presentation/    # UI layer (screens, widgets, providers)
│   │   └── features/    # Feature-specific UI components
│   │       ├── home/           # Home screen with bottom navigation
│   │       ├── landing/        # Landing/intro screen
│   │       ├── registration/   # User registration
│   │       ├── login/          # User login
│   │       ├── live_tracking/  # Live GPS tracking
│   │       ├── tracking_history/ # Activity history
│   │       ├── profile/        # User profile management
│   │       ├── settings/       # App settings
│   │       └── Map/            # Map components
│   ├── theme/           # App theming (light/dark)
│   └── const/           # App constants
├── assets/              # Static assets (fonts, images)
└── android/ios/         # Platform-specific code
```

## 🔗 API Endpoints

### Authentication & User Management
- `POST /api/users/register` - Register new user
- `POST /api/users/login` - User login (returns access and refresh tokens)
- `POST /api/users/logout` - Logout user and invalidate refresh token
- `POST /api/users/refresh-token` - Get new access token using refresh token
- `PUT /api/users/profile` - Update user profile (firstname, lastname)
- `PUT /api/users/change-password` - Change user password
- `POST /api/users/profile-picture` - Upload profile picture (legacy - local storage)
- `GET /api/users/profile-picture/:id` - Get user's profile picture

### Avatar Management (S3 Cloud Storage)
- `POST /api/avatar/upload-url` - Get presigned URL for S3 upload
- `POST /api/avatar/confirm` - Confirm avatar upload and update user profile

### Activities
- `GET /api/activities` - Get activities list (paginated, supports filtering)
- `GET /api/activities/:activityId` - Get specific activity details
- `POST /api/activities` - Create new activity
- `PATCH /api/activities/:activityId` - Update activity
- `DELETE /api/activities/:activityId` - Delete activity

### Friend Requests
- `POST /api/friends/requests` - Send friend request to another user
- `GET /api/friends/requests/pending` - Get list of pending friend requests
- `POST /api/friends/requests/:requestId/accept` - Accept a friend request
- `POST /api/friends/requests/:requestId/reject` - Reject a friend request
- `DELETE /api/friends/requests/:requestId` - Cancel a sent friend request
- `GET /api/friends/status/:userId` - Get friendship status with another user

### Likes
- `GET /api/activities/:activityId/likes` - Get like status for current user
- `POST /api/activities/:activityId/likes` - Like an activity
- `DELETE /api/activities/:activityId/likes` - Unlike an activity

### Comments
- `GET /api/activities/:activityId/comments` - Get all comments for an activity
- `GET /api/activities/:activityId/comments/:commentId` - Get specific comment
- `POST /api/activities/:activityId/comments` - Create a new comment
- `PATCH /api/activities/:activityId/comments/:commentId` - Update a comment
- `DELETE /api/activities/:activityId/comments/:commentId` - Delete a comment

## 🏃‍♀️ App Features

### Screen Features
- **Landing Screen**: App introduction and navigation to registration/login
- **Registration**: User account creation with email validation and password requirements
- **Login**: User authentication with automatic token refresh support
- **Home Screen**: Main navigation hub with bottom tab bar (Track, Activities, Profile)
- **Track Screen**: Start and manage live workout tracking with GPS
- **Live Tracking**: Real-time GPS tracking during workouts with map visualization
- **Activities Feed**: Browse and view activities from yourself and friends
- **Profile Screen**: Comprehensive user profile management with:
  - Avatar upload and display (S3 + CloudFront CDN)
  - Profile editing (firstname, lastname)
  - User statistics (total activities, distance, etc.)
  - Settings access
- **Tracking History**: View past activities with detailed statistics and map visualization
- **Tracking History Details**: Detailed view of individual activities with route visualization
- **Settings Screen**: App configuration, theme preferences, password change, and account management

## 🛡️ Security Features

- **JWT Authentication**: Secure token-based authentication with access and refresh tokens
- **Token Refresh**: Automatic token refresh mechanism for seamless user experience
- **Password Hashing**: bcrypt for secure password storage
- **Input Validation**: Comprehensive validation on both frontend and backend (Joi, class-validator)
- **Secure Storage**: Encrypted local storage for sensitive data (tokens, user info) using Flutter Secure Storage
- **CORS Protection**: Configured CORS policies for API security
- **Helmet Security**: Security headers for API protection
- **Session Management**: Robust session handling with offline mode support
- **Environment-based Secrets**: Production secrets stored in environment variables
- **HTTPS Support**: Production API uses HTTPS for secure communication

## 🚧 Development

### Running Tests
```bash
# Backend tests
cd RythmRun_backend_nodejs
npm test

# Frontend tests
cd rythmrun_frontend_flutter
flutter test
```

### Building for Production

#### Backend Build
```bash
cd RythmRun_backend_nodejs
npm run build
npm start  # Production server
```

#### Frontend Build

**Android:**
```bash
cd rythmrun_frontend_flutter
flutter build apk --release  # APK for direct installation
flutter build appbundle --release  # AAB for Google Play Console
```

**iOS:**
```bash
cd rythmrun_frontend_flutter
flutter build ios --release
# Then archive in Xcode for App Store/TestFlight
```

**Output Locations:**
- Android APK: `build/app/outputs/flutter-apk/app-release.apk`
- Android AAB: `build/app/outputs/bundle/release/app-release.aab`
- iOS: Open `ios/Runner.xcworkspace` in Xcode to archive

## 📱 Mobile App Requirements

### Android
- Minimum SDK: 21 (Android 5.0)
- Target SDK: 36 (Android 14+)
- Permissions: Location, Storage, Internet, Camera (for profile pictures)
- Bundle ID: `com.github.cosmicsaurabh.rythmrun`
- Current Version: 1.0.0+7

### iOS
- Minimum iOS: 12.0
- Permissions: Location, Photo Library

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Create a Pull Request

## 📄 License

This project is licensed under the ISC License.

## 🚀 Deployment

### Backend Deployment
The backend is currently deployed on **Railway**:
- **Production URL**: `--`
- **Environment**: Production environment configured
- **Database**: PostgreSQL hosted on Railway
- **CDN**: CloudFront CDN configured for avatar images (`--`)

### Frontend Deployment
- **Android**: Ready for Google Play Store deployment
- **iOS**: Ready for App Store deployment via TestFlight
- **Environment Detection**: Automatically switches between dev/prod based on build mode

### Environment Configuration
- **Development**: Uses local backend URL (configurable in `app_config.dart`)
- **Production**: Uses Railway production URL automatically
- **CloudFront**: Configured for both dev and prod environments

## 📋 Current Version

- **Version**: 1.0.0+7
- **Latest Features**: 
  - Avatar/Profile Picture Upload with S3 Cloud Storage
  - CloudFront CDN integration
  - Production deployment on Railway
  - Multi-environment support
  - Enhanced session management with offline mode
- **Release Date**: November 2025

## 🐛 Known Issues & Requirements

- **AWS S3 Configuration**: AWS S3 credentials must be configured in backend `.env` for avatar uploads to work
- **CloudFront CDN**: CloudFront distribution is configured and active for avatar image delivery
- **Maps**: Uses offline map support (flutter_map) - no Google Maps API key required
- **Backend Environment**: Ensure `.env` file is properly configured with all required variables

## 📞 Support

For support and questions, please create an issue in the GitHub repository.

---

**RythmRun** - Where rhythm meets running! 🎵🏃‍♂️ 
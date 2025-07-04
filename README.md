# RythmRun 🏃‍♂️

A comprehensive fitness tracking application that combines the power of rhythm and running. RythmRun helps users track their fitness activities, connect with friends, and stay motivated through social features and real-time tracking.

## 🏗️ Project Architecture

RythmRun is built as a full-stack application with:

- **Frontend**: Flutter mobile app with clean architecture
- **Backend**: Node.js/Express API with TypeScript
- **Database**: PostgreSQL with Prisma ORM
- **Authentication**: JWT-based authentication system

## 📱 Features

### Core Features
- **User Authentication**: Secure registration and login system
- **Activity Tracking**: Create, view, and manage fitness activities
- **Live Tracking**: Real-time GPS tracking during workouts
- **Social Features**: Connect with friends, like activities, and comment
- **Profile Management**: User profiles with profile picture uploads
- **Tracking History**: View past activities and progress

### Technical Features
- **Offline Capability**: Local SQLite database for offline tracking
- **Real-time Location**: GPS tracking with geolocator
- **Maps Integration**: Google Maps for visual tracking
- **Secure Storage**: Encrypted local storage for sensitive data

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
   JWT_SECRET="your-secret-key"
   PORT=3000
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

   The API will be running on `http://localhost:3000`

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
   Update `lib/core/config/app_config.dart` with your backend URL:
   ```dart
   // Update the base URL to match your backend server
   static const String baseUrl = 'http://YOUR_IP:3000/api';
   ```

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
- **File Uploads**: Multer
- **Validation**: Joi & class-validator
- **Logging**: Winston
- **Security**: Helmet, CORS

### Frontend
- **Framework**: Flutter
- **Language**: Dart
- **State Management**: Riverpod
- **HTTP Client**: http package
- **Local Database**: SQLite (sqflite)
- **Maps**: Google Maps Flutter
- **GPS Tracking**: Geolocator
- **Secure Storage**: Flutter Secure Storage
- **Permissions**: Permission Handler
- **Authentication**: JWT Decoder

## 📂 Project Structure

### Backend Structure
```
RythmRun_backend_nodejs/
├── src/
│   ├── controllers/     # API request handlers
│   ├── services/        # Business logic
│   ├── routes/          # API endpoints
│   ├── middleware/      # Authentication & validation
│   ├── models/          # DTOs and type definitions
│   ├── config/          # Application configuration
│   └── utils/           # Utility functions
├── prisma/              # Database schema and migrations
├── uploads/             # File upload directory
└── dist/               # Compiled JavaScript
```

### Frontend Structure
```
rythmrun_frontend_flutter/
├── lib/
│   ├── core/            # Core functionality (config, networking)
│   ├── data/            # Data layer (repositories, datasources)
│   ├── domain/          # Domain layer (entities, use cases)
│   ├── presentation/    # UI layer (screens, widgets)
│   │   └── features/    # Feature-specific UI components
│   │       ├── home/
│   │       ├── tracking/
│   │       ├── profile/
│   │       └── ...
│   └── theme/           # App theming
├── assets/              # Static assets (fonts, images)
└── android/ios/         # Platform-specific code
```

## 🔗 API Endpoints

### Authentication
- `POST /api/users/register` - Register new user
- `POST /api/users/login` - User login
- `GET /api/users/profile` - Get user profile
- `PUT /api/users/profile` - Update user profile
- `POST /api/users/profile-picture` - Upload profile picture

### Activities
- `POST /api/activities` - Create new activity
- `GET /api/activities` - Get activities list
- `GET /api/activities/:id` - Get specific activity
- `PUT /api/activities/:id` - Update activity
- `DELETE /api/activities/:id` - Delete activity

### Social Features
- `GET /api/friends` - Get friends list
- `POST /api/friends/request` - Send friend request
- `POST /api/activities/:id/likes` - Like/unlike activity
- `POST /api/activities/:id/comments` - Comment on activity

## 🏃‍♀️ App Features

### Screen Features
- **Landing Screen**: App introduction and navigation
- **Registration**: User account creation with validation
- **Login**: User authentication
- **Home**: Activity feed and navigation hub
- **Track**: Start and manage workout tracking
- **Live Tracking**: Real-time GPS tracking during workouts
- **Profile**: User profile management
- **Tracking History**: View past activities and statistics
- **Settings**: App configuration and preferences

## 🛡️ Security Features

- **JWT Authentication**: Secure token-based authentication
- **Password Hashing**: bcrypt for password security
- **Input Validation**: Comprehensive validation on both frontend and backend
- **Secure Storage**: Encrypted local storage for sensitive data
- **CORS Protection**: Configured CORS policies
- **Helmet Security**: Security headers for API protection

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
```bash
# Backend build
cd RythmRun_backend_nodejs
npm run build

# Frontend build
cd rythmrun_frontend_flutter
flutter build apk --release  # Android
flutter build ios --release  # iOS
```

## 📱 Mobile App Requirements

### Android
- Minimum SDK: 21 (Android 5.0)
- Target SDK: 34 (Android 14)
- Permissions: Location, Storage, Internet

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

## 🐛 Known Issues

- Google Maps API key needs to be configured for maps functionality
- Profile picture upload requires proper file permissions setup

## 📞 Support

For support and questions, please create an issue in the GitHub repository.

---

**RythmRun** - Where rhythm meets running! 🎵🏃‍♂️ 
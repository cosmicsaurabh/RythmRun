# RythmRun Flutter Frontend - Resume Project Requirements

## 1. Project Overview

### Purpose
A modern Flutter fitness tracking app for showcasing full-stack mobile development skills. Features GPS tracking, social interactions, and real-time activity monitoring - perfect for demonstrating proficiency in Flutter, state management, API integration, and mobile development best practices.

### Tech Stack (Resume Highlights)
- **Flutter 3.16+** with Dart 3.0+ - Modern mobile development
- **Riverpod + Hooks** - Advanced state management 
- **Clean Architecture** - Scalable code organization
- **Dio HTTP Client** - RESTful API integration
- **Flutter Map + GPS** - Real-time location tracking
- **Material Design 3** - Modern UI/UX
- **Internationalization** - Multi-language support
- **Comprehensive Testing** - Unit, Widget, Integration tests

## 2. Core Features (Resume Highlights)

### 🔐 Authentication & User Management
- **JWT Authentication** with secure storage
- **Form validation** with real-time feedback
- **Password reset** flow with email integration
- **User profile** management with image upload

### 📍 Activity Tracking (GPS & Real-time)
- **Real-time GPS tracking** with high accuracy
- **Live metrics calculation** (distance, speed, duration)
- **Interactive maps** with route visualization
- **Background location** services
- **Activity persistence** and offline capability

### 📊 Activity Management
- **Infinite scroll pagination** for activity lists
- **Detailed activity views** with charts and maps
- **Search and filtering** capabilities
- **Data export** functionality

### 👥 Social Features
- **Friend system** with request management
- **Activity feed** with real-time updates
- **Like/comment system** on activities
- **User search** with debounced input

## 3. Architecture (Clean Architecture)
```
lib/
├── core/                    # Utilities and configurations
├── data/                   # API clients, models, repositories
├── domain/                 # Business logic and entities  
├── presentation/           # UI screens and widgets
│   ├── common/            # Shared components
│   ├── auth/              # Login/Registration
│   ├── activity/          # Tracking and history
│   ├── social/            # Community features
│   └── settings/          # User preferences
└── main.dart              # App entry point
```

**Key Patterns**: MVVM, Repository, Provider, Dependency Injection

## 4. Essential Dependencies (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  hooks_riverpod: ^2.4.0
  flutter_hooks: ^0.20.3
  
  # HTTP & API
  dio: ^5.3.0
  
  # Location & Maps
  geolocator: ^10.1.0
  flutter_map: ^6.0.1
  latlong2: ^0.9.0
  
  # Storage
  shared_preferences: ^2.2.0
  flutter_secure_storage: ^9.0.0
  
  # UI
  google_nav_bar: ^5.0.6
  cached_network_image: ^3.3.0
  
  # Utils
  intl: ^0.19.0
  equatable: ^2.0.5
```

## 5. Key Implementation Examples

### State Management with Riverpod
```dart
// Authentication Provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref;
  
  AuthNotifier(this.ref) : super(AuthState.initial());
  
  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    try {
      final response = await ref.read(authRepositoryProvider).login(email, password);
      state = AuthState.authenticated(response.user, response.token);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}
```

### GPS Tracking Service
```dart
class LocationTrackingService {
  Stream<Position> get positionStream => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
    ),
  );
  
  Future<bool> requestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse || 
           permission == LocationPermission.always;
  }
}
```

### Activity Tracking Provider
```dart
final activityTrackingProvider = StateNotifierProvider<ActivityTrackingNotifier, ActivityTrackingState>((ref) {
  return ActivityTrackingNotifier(ref);
});

class ActivityTrackingNotifier extends StateNotifier<ActivityTrackingState> {
  final Ref ref;
  StreamSubscription<Position>? _positionSubscription;
  
  ActivityTrackingNotifier(this.ref) : super(ActivityTrackingState.initial());
  
  void startTracking() {
    state = state.copyWith(isTracking: true, startTime: DateTime.now());
    _positionSubscription = ref.read(locationServiceProvider).positionStream.listen((position) {
      _updateLocation(position);
    });
  }
  
  void _updateLocation(Position position) {
    final newPoint = LatLng(position.latitude, position.longitude);
    final updatedRoute = [...state.routePoints, newPoint];
    final distance = _calculateDistance(updatedRoute);
    
    state = state.copyWith(
      routePoints: updatedRoute,
      distance: distance,
      currentSpeed: position.speed * 3.6, // m/s to km/h
    );
  }
}
```

## 6. API Integration

### HTTP Client Setup
```dart
@RestApi(baseUrl: "http://localhost:8080/api/")
abstract class ApiClient {
  factory ApiClient(Dio dio) = _ApiClient;

  @POST("/auth/login")
  Future<LoginResponse> login(@Body() LoginRequest request);
  
  @GET("/private/activity/all")
  Future<PageResponse<ActivityResponse>> getActivities(
    @Query("page") int page,
    @Query("size") int size,
  );
  
  @POST("/private/activity")
  Future<ActivityResponse> createActivity(@Body() ActivityRequest request);
}
```

## 7. Testing Strategy (Resume Skills)

### Unit Tests
```dart
void main() {
  group('AuthNotifier Tests', () {
    test('should login successfully with valid credentials', () async {
      // Arrange
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(mockAuthRepository),
      ]);
      
      // Act
      await container.read(authProvider.notifier).login('test@email.com', 'password');
      
      // Assert
      expect(container.read(authProvider).isAuthenticated, isTrue);
    });
  });
}
```

### Widget Tests
```dart
void main() {
  testWidgets('Login screen should validate email format', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    
    await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    
    expect(find.text('Please enter a valid email'), findsOneWidget);
  });
}
```

## 8. Performance & Best Practices

### Memory Management
- **AutoDispose providers** for temporary state
- **Efficient ListView** with proper keys
- **Image caching** and compression
- **Background location** optimization

### Code Quality
- **Dart analysis** with strict linting rules
- **Documentation** for public APIs
- **Error handling** with user-friendly messages
- **Accessibility** compliance

## 9. Quick Setup Commands

```bash
# Project setup
flutter create rythmrun_app
cd rythmrun_app

# Add dependencies
flutter pub add hooks_riverpod flutter_hooks dio geolocator flutter_map

# Run the app
flutter run

# Run tests
flutter test

# Build release
flutter build apk --release
```

## 10. Resume Project Highlights

### Technical Skills Demonstrated
✅ **Flutter & Dart** - Modern mobile development
✅ **State Management** - Complex app state with Riverpod
✅ **Clean Architecture** - Scalable code organization
✅ **API Integration** - RESTful services with error handling
✅ **Real-time Features** - GPS tracking and live updates
✅ **Testing** - Comprehensive test coverage
✅ **Performance** - Optimized for production use
✅ **Modern Practices** - Latest Flutter patterns and conventions

### Project Complexity
- **Real-time GPS tracking** with background processing
- **Social networking** features with friend management
- **Complex state management** across multiple screens
- **File uploads** and image handling
- **Offline capabilities** and data persistence
- **Internationalization** support

This project demonstrates full-stack mobile development skills perfect for showcasing modern Flutter expertise on your resume! 🚀

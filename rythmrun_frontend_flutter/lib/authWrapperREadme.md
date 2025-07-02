1. App starts:
   AuthWrapper → shows LandingScreen (unauthenticated)

2. User taps "Sign In":
   Navigator.pushNamed('/login')
   ┌─────────────────┐
   │   LoginScreen   │ ← Visible
   ├─────────────────┤
   │   AuthWrapper   │ ← Hidden, but still watching session
   │ (LandingScreen) │
   └─────────────────┘

3. User logs in successfully:
   Session state → authenticated
   ┌─────────────────┐
   │   LoginScreen   │ ← Still visible
   ├─────────────────┤
   │   AuthWrapper   │ ← Rebuilt, now shows HomeScreen
   │  (HomeScreen)   │   (but hidden behind LoginScreen)
   └─────────────────┘

4. Navigator.pop():
   ┌─────────────────┐
   │   AuthWrapper   │ ← Now visible
   │  (HomeScreen)   │   Shows HomeScreen because authenticated!
   └─────────────────┘
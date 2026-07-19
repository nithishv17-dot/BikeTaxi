import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/driver_screen.dart';
import 'screens/ride_status_screen.dart';
import 'services/api_service.dart';
import 'services/session_service.dart';
import 'services/socket_service.dart';
import 'theme/premium_ui.dart';

final GoRouter _router = GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      redirect: (context, state) {
        final session = SessionService.loadSession();
        if (session == null) {
          return '/login';
        }
        ApiService.token = session['token'];
        final role = session['role'] ?? 'user';
        if (role == 'driver') {
          return '/driver';
        } else {
          return '/home';
        }
      },
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) {
        final session = SessionService.loadSession();
        if (session == null) {
          return const LoginScreen();
        }
        ApiService.token = session['token'];
        final userId = session['userId'] ?? '';
        return HomeScreen(userId: userId);
      },
    ),
    GoRoute(
      path: '/driver',
      builder: (context, state) {
        final session = SessionService.loadSession();
        if (session == null) {
          return const LoginScreen();
        }
        ApiService.token = session['token'];
        final userId = session['userId'] ?? '';
        return DriverScreen(driverId: userId);
      },
    ),
    GoRoute(
      path: '/ride-status/:rideId',
      builder: (context, state) {
        final session = SessionService.loadSession();
        if (session == null) {
          return const LoginScreen();
        }
        ApiService.token = session['token'];
        final rideId = state.pathParameters['rideId']!;
        final isDriver = state.uri.queryParameters['driver'] == 'true';
        return RideStatusScreen(rideId: rideId, isDriver: isDriver);
      },
    ),
  ],
);

void main() {
  SocketService.connect();
  runApp(const BikeTaxiApp());
}

class BikeTaxiApp extends StatelessWidget {
  const BikeTaxiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = AppPalette.primary;
    final baseTextTheme = GoogleFonts.poppinsTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppPalette.background,
        textTheme: baseTextTheme.apply(
          bodyColor: AppPalette.slate900,
          displayColor: AppPalette.slate900,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: AppPalette.slate900,
          titleTextStyle: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppPalette.slate900,
            letterSpacing: -0.4,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          color: Colors.white.withOpacity(0.06),
          shadowColor: Colors.black.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppPalette.slate700,
          ),
          hintStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppPalette.slate700,
          ),
          prefixIconColor: AppPalette.slate700,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: seedColor, width: 1.8),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 1,
            backgroundColor: seedColor,
            foregroundColor: AppPalette.navy900,
            minimumSize: const Size(double.infinity, 56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppPalette.background,
          contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
            color: AppPalette.slate900,
            fontWeight: FontWeight.w600,
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/driver_screen.dart';
import 'services/api_service.dart';
import 'services/session_service.dart';
import 'services/socket_service.dart';
import 'theme/premium_ui.dart';

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
      ThemeData(brightness: Brightness.light).textTheme,
    );

    // Check for saved session
    final session = SessionService.loadSession();
    Widget homeWidget;
    if (session != null) {
      ApiService.token = session['token'];
      final role = session['role'] ?? 'user';
      final userId = session['userId']!;
      if (role == 'driver') {
        homeWidget = DriverScreen(driverId: userId);
      } else {
        homeWidget = HomeScreen(userId: userId);
      }
    } else {
      homeWidget = const LoginScreen();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
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
          color: Colors.white.withOpacity(0.92),
          shadowColor: const Color(0xFF0F172A).withOpacity(0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.86),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppPalette.slate500,
          ),
          hintStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            color: AppPalette.slate500,
          ),
          prefixIconColor: AppPalette.slate500,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
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
            foregroundColor: Colors.white,
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
          backgroundColor: AppPalette.navy900,
          contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: homeWidget,
    );
  }
}

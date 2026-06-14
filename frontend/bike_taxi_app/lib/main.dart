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
      ThemeData(brightness: Brightness.dark).textTheme,
    );

    // Check for saved session
    final session = SessionService.loadSession();
    Widget homeWidget;
    if (session != null) {
      ApiService.token = session['token'];
      final role = session['role'] ?? 'user';
      final userId = session['userId']!;
      homeWidget = SessionInitPage(userId: userId, role: role);
    } else {
      homeWidget = const LoginScreen();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
      home: homeWidget,
    );
  }
}

class SessionInitPage extends StatefulWidget {
  final String userId;
  final String role;

  const SessionInitPage({super.key, required this.userId, required this.role});

  @override
  State<SessionInitPage> createState() => _SessionInitPageState();
}

class _SessionInitPageState extends State<SessionInitPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _goToHome());
  }

  void _goToHome() {
    if (!mounted) return;
    if (widget.role == 'driver') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DriverScreen(driverId: widget.userId),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(userId: widget.userId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: AppPalette.primary,
        ),
      ),
    );
  }
}

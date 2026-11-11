import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController identifierController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String result = "";
  bool isLoading = false;
  bool isGuestLoading = false;
  bool isGoogleLoading = false;
  bool obscurePassword = true;
  bool isDriver = false;

  String get selectedRole => isDriver ? "driver" : "rider";

  void loginUser() async {
    if (identifierController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      setState(() {
        result = "Please enter username/phone and password";
      });
      return;
    }

    setState(() {
      isLoading = true;
      result = "";
    });

    try {
      print("Login button pressed");

      final response = await ApiService.login(
        identifierController.text.trim(),
        passwordController.text.trim(),
        role: isDriver ? "driver" : "user",
      );

      print("LOGIN RESPONSE: $response");

      if (response["message"] == "Login successful" &&
          response["token"] != null &&
          response["userId"] != null) {
        ApiService.token = response["token"];
        final userRole = response["role"]?.toString() ?? (isDriver ? "driver" : "user");
        final sessionId = response["sessionId"]?.toString();
        SessionService.saveSession(
          response["token"],
          response["userId"],
          userRole,
          sessionId: sessionId,
          name: response["name"]?.toString(),
          phone: response["phone"]?.toString(),
        );

        SocketService.connect(
          token: response["token"],
          userId: response["userId"],
          sessionId: sessionId,
        );
        SocketService.authenticate(
          token: response["token"],
          userId: response["userId"],
          sessionId: sessionId,
        );

        if (!mounted) return;

        if (userRole == "driver") {
          try {
            await ApiService.toggleDriver(response["userId"], isAvailable: true);
          } catch (e) {
            print("Auto-set online error: $e");
          }
          if (!mounted) return;
          context.go('/driver');
        } else {
          context.go('/home');
        }
      } else {
        setState(() {
          result = response["message"] ?? "Login failed";
        });
      }
    } catch (e) {
      print("LOGIN ERROR: $e");

      setState(() {
        result = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void loginAsGuest() async {
    setState(() {
      isGuestLoading = true;
      result = "";
    });

    try {
      final role = selectedRole;
      final response = await ApiService.post('/api/auth/guest-login', {
        'role': role,
      });

      if (response['token'] != null) {
        final token = response['token']?.toString() ?? '';
        final userId = (response['user']?['id'] ?? response['userId'])?.toString() ?? '';
        final userRole = (response['user']?['role'] ?? response['role'])?.toString() ?? role;
        final sessionId = response['sessionId']?.toString();

        ApiService.token = token;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('user_id', userId);
        await prefs.setString('user_role', userRole);

        SessionService.saveSession(
          token,
          userId,
          userRole,
          sessionId: sessionId,
          name: response['user']?['name']?.toString() ?? response['name']?.toString(),
          phone: response['user']?['phone']?.toString() ?? response['phone']?.toString(),
        );

        SocketService.connect(token: token, userId: userId, sessionId: sessionId);
        SocketService.authenticate(token: token, userId: userId, sessionId: sessionId);

        if (!mounted) return;

        if (userRole == 'driver' || role == 'driver') {
          try {
            await ApiService.toggleDriver(userId, isAvailable: true);
          } catch (e) {
            debugPrint("Auto-set online error: $e");
          }
          if (!mounted) return;
          context.go('/captain-home');
        } else {
          context.go('/home');
        }
      } else {
        setState(() {
          result = response['message']?.toString() ?? "Guest login failed";
        });
      }
    } catch (e) {
      debugPrint("GUEST LOGIN ERROR: $e");
      setState(() {
        result = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          isGuestLoading = false;
        });
      }
    }
  }

  void loginWithGoogle() async {
    setState(() {
      isGoogleLoading = true;
      result = "";
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: kIsWeb
            ? '57219954065-obscrq1h5ohuaeiclt58msjm7kjmh5v6.apps.googleusercontent.com'
            : null,
        scopes: const ['email', 'profile', 'openid'],
      );

      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account != null) {
        final GoogleSignInAuthentication auth = await account.authentication;
        final String? idToken = auth.idToken;

        final response = await ApiService.post('/api/auth/google-login', {
          'idToken': idToken,
          'role': selectedRole,
          'email': account.email,
          'name': account.displayName,
          'avatar': account.photoUrl,
        });

        if (response['success'] == true || response['token'] != null) {
          final token = response['token']?.toString() ?? '';
          final userId = (response['user']?['id'] ?? response['userId'])?.toString() ?? '';
          final userRole = (response['user']?['role'] ?? response['role'])?.toString() ?? selectedRole;
          final sessionId = response['sessionId']?.toString();

          ApiService.token = token;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
          await prefs.setString('user_id', userId);
          await prefs.setString('user_role', userRole);

          SessionService.saveSession(
            token,
            userId,
            userRole,
            sessionId: sessionId,
            name: response['user']?['name']?.toString() ?? account.displayName,
            phone: response['user']?['phone']?.toString() ?? account.email,
          );

          SocketService.connect(token: token, userId: userId, sessionId: sessionId);
          SocketService.authenticate(token: token, userId: userId, sessionId: sessionId);

          if (!mounted) return;

          if (userRole == 'driver' || selectedRole == 'driver') {
            try {
              await ApiService.toggleDriver(userId, isAvailable: true);
            } catch (e) {
              debugPrint("Auto-set online error: $e");
            }
            if (!mounted) return;
            context.go('/captain-home');
          } else {
            context.go('/home');
          }
        } else {
          setState(() {
            result = response['message']?.toString() ?? "Google Sign-In failed";
          });
        }
      }
    } catch (e) {
      debugPrint("GOOGLE AUTH ERROR: $e");
      setState(() {
        result = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          isGoogleLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    identifierController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RevealMotion(
                      delay: const Duration(milliseconds: 40),
                      beginOffset: const Offset(0, -0.1),
                      child: ReflectiveBanner(
                        colors: const [AppPalette.primary, Color(0xFF4F46E5)],
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Icon(
                                    Icons.two_wheeler_rounded,
                                    color: Colors.white,
                                    size: 34,
                                  ),
                                  SizedBox(height: 14),
                                  Text(
                                    "DotTaxi",
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "Fast booking, live tracking, and seamless payment in one premium experience.",
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.24),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.asset(
                                  "assets/icon/app_icon.jpg",
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    RevealMotion(
                      delay: const Duration(milliseconds: 140),
                      child: ReflectionCard(
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              "Welcome Back",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isDriver
                                  ? "Sign in to accept rides, manage availability, and stay connected with passengers."
                                  : "Sign in to request rides, monitor drivers, and manage every trip.",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppPalette.slate500,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ChoiceChip(
                                  label: const Text("Rider"),
                                  selected: !isDriver,
                                  onSelected: (selected) {
                                    setState(() {
                                      isDriver = false;
                                    });
                                  },
                                ),
                                const SizedBox(width: 12),
                                ChoiceChip(
                                  label: const Text("Driver"),
                                  selected: isDriver,
                                  onSelected: (selected) {
                                    setState(() {
                                      isDriver = selected;
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            TextField(
                              controller: identifierController,
                              keyboardType: TextInputType.text,
                              decoration: const InputDecoration(
                                labelText: "Name or Phone Number",
                                hintText: "Enter name or phone number",
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: passwordController,
                              obscureText: obscurePassword,
                              decoration: InputDecoration(
                                labelText: "Password",
                                hintText: "Enter password",
                                prefixIcon: const Icon(Icons.lock_rounded),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      obscurePassword = !obscurePassword;
                                    });
                                  },
                                  icon: Icon(
                                    obscurePassword
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppPalette.primary.withOpacity(isLoading ? 0.18 : 0.28),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: isLoading ? null : loginUser,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  child: isLoading
                                      ? const SizedBox(
                                          key: ValueKey("loading"),
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          isDriver ? "Login as Driver" : "Login",
                                          key: const ValueKey("idle"),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                context.push('/register');
                              },
                              child: const Text("Create Account"),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: Divider(color: AppPalette.slate300.withOpacity(0.5))),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    "OR",
                                    style: TextStyle(
                                      color: AppPalette.slate500,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: AppPalette.slate300.withOpacity(0.5))),
                              ],
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 54),
                                side: BorderSide(color: AppPalette.slate300.withOpacity(0.7)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              onPressed: (isLoading || isGuestLoading || isGoogleLoading) ? null : loginAsGuest,
                              icon: isGuestLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: AppPalette.primary,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person_outline_rounded,
                                      color: AppPalette.primary,
                                      size: 22,
                                    ),
                              label: Text(
                                isGuestLoading
                                    ? "Logging in as Guest..."
                                    : (isDriver ? "Continue as Guest Driver" : "Continue as Guest Rider"),
                                style: const TextStyle(
                                  color: AppPalette.slate900,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 54),
                                side: BorderSide(color: AppPalette.slate300.withOpacity(0.7)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              onPressed: (isLoading || isGuestLoading || isGoogleLoading) ? null : loginWithGoogle,
                              icon: isGoogleLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: AppPalette.primary,
                                      ),
                                    )
                                  : Image.network(
                                      "https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Google_%22G%22_Logo.svg/512px-Google_%22G%22_Logo.svg.png",
                                      height: 22,
                                      errorBuilder: (context, error, stackTrace) => const Icon(
                                        Icons.account_circle_rounded,
                                        color: AppPalette.primary,
                                        size: 22,
                                      ),
                                    ),
                              label: Text(
                                isGoogleLoading ? "Connecting to Google..." : "Continue with Google",
                                style: const TextStyle(
                                  color: AppPalette.slate900,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              child: result.isEmpty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF93000A).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFFFB4AB).withOpacity(0.3),
                                          ),
                                        ),
                                        child: Text(
                                          result,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFFFB4AB),
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  String message = "";
  bool isLoading = false;
  bool isGuestLoading = false;
  bool isGoogleLoading = false;
  bool obscurePassword = true;
  bool isDriver = false;

  String get selectedRole => isDriver ? "driver" : "rider";

  void registerUser() async {
    if (nameController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      setState(() {
        message = "Please fill all fields";
      });
      return;
    }

    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.register(
        nameController.text.trim(),
        phoneController.text.trim(),
        passwordController.text.trim(),
        role: isDriver ? "driver" : "user",
      );

      print("REGISTER SUCCESS: $response");

      setState(() {
        message = response["message"] ?? "Registration successful";
      });

      if (response["message"] == "User registered successfully") {
        if (!mounted) return;
        context.go('/login');
      }
    } catch (e) {
      print("REGISTER ERROR: $e");

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
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
      message = "";
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
          message = response['message']?.toString() ?? "Guest login failed";
        });
      }
    } catch (e) {
      debugPrint("GUEST LOGIN ERROR: $e");
      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
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
      message = "";
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: kIsWeb ? AppConfig.googleClientId : null,
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
            message = response['message']?.toString() ?? "Google Sign-In failed";
          });
        }
      }
    } catch (e) {
      debugPrint("GOOGLE AUTH ERROR: $e");
      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
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
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PremiumBackdrop(
        accentColor: AppPalette.primary,
        secondaryColor: AppPalette.secondary,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4A261).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.two_wheeler_rounded,
                              size: 20,
                              color: Color(0xFFF4A261),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "Dottaxi",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    RevealMotion(
                      delay: const Duration(milliseconds: 80),
                      child: ReflectionCard(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              "Create Account",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Set up your profile and start booking in seconds.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppPalette.slate500,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ChoiceChip(
                                  label: const Text("Rider"),
                                  visualDensity: VisualDensity.compact,
                                  selected: !isDriver,
                                  onSelected: (selected) {
                                    setState(() {
                                      isDriver = false;
                                    });
                                  },
                                ),
                                const SizedBox(width: 10),
                                ChoiceChip(
                                  label: const Text("Driver"),
                                  visualDensity: VisualDensity.compact,
                                  selected: isDriver,
                                  onSelected: (selected) {
                                    setState(() {
                                      isDriver = selected;
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 13,
                                  horizontal: 16,
                                ),
                                labelText: "Name",
                                hintText: "Enter full name",
                                prefixIcon: Icon(Icons.person_rounded),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 13,
                                  horizontal: 16,
                                ),
                                labelText: "Phone",
                                hintText: "Enter mobile number",
                                prefixIcon: Icon(Icons.phone_rounded),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: passwordController,
                              obscureText: obscurePassword,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                  horizontal: 16,
                                ),
                                labelText: "Password",
                                hintText: "Create password",
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
                            const SizedBox(height: 12),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppPalette.primary.withValues(alpha: isLoading ? 0.18 : 0.28),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 44),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                onPressed: isLoading ? null : registerUser,
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
                                      : const Text(
                                          "Register",
                                          key: ValueKey("idle"),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                              ),
                              onPressed: () {
                                context.go('/login');
                              },
                              child: const Text(
                                "Already have an account? Login",
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(child: Divider(color: AppPalette.slate300.withValues(alpha: 0.5))),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Text(
                                    "OR",
                                    style: TextStyle(
                                      color: AppPalette.slate500,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: AppPalette.slate300.withValues(alpha: 0.5))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                side: BorderSide(color: AppPalette.slate300.withValues(alpha: 0.7)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: (isLoading || isGuestLoading || isGoogleLoading) ? null : loginAsGuest,
                              icon: isGuestLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: AppPalette.primary,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.person_outline_rounded,
                                      color: AppPalette.primary,
                                      size: 20,
                                    ),
                              label: Text(
                                isGuestLoading
                                    ? "Logging in as Guest..."
                                    : (isDriver ? "Continue as Guest Driver" : "Continue as Guest Rider"),
                                style: const TextStyle(
                                  color: AppPalette.slate900,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 44),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                side: BorderSide(color: AppPalette.slate300.withValues(alpha: 0.7)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: (isLoading || isGuestLoading || isGoogleLoading) ? null : loginWithGoogle,
                              icon: isGoogleLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: AppPalette.primary,
                                      ),
                                    )
                                  : Image.network(
                                      "https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Google_%22G%22_Logo.svg/512px-Google_%22G%22_Logo.svg.png",
                                      height: 20,
                                      errorBuilder: (context, error, stackTrace) => const Icon(
                                        Icons.account_circle_rounded,
                                        color: AppPalette.primary,
                                        size: 20,
                                      ),
                                    ),
                              label: Text(
                                isGoogleLoading ? "Connecting to Google..." : "Continue with Google",
                                style: const TextStyle(
                                  color: AppPalette.slate900,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              child: message.isEmpty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.1),
                                          ),
                                        ),
                                        child: Text(
                                          message,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppPalette.slate900,
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

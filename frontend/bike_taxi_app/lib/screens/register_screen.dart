import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../theme/premium_ui.dart';
import 'driver_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';


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
  bool obscurePassword = true;
  bool isDriver = false;

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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
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

  void loginWithGoogle() async {
    setState(() {
      isLoading = true;
      message = "";
    });

    final selectedEmail = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Image.network(
                      "https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Google_%22G%22_Logo.svg/512px-Google_%22G%22_Logo.svg.png",
                      height: 24,
                      errorBuilder: (c, e, s) => const Icon(Icons.g_mobiledata_rounded, color: AppPalette.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Sign in with Google",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  "Choose an account to continue to RideGo",
                  style: TextStyle(
                    color: AppPalette.slate500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppPalette.primary,
                    child: Text("NK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: const Text("Nithish Kumar", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("nithish.kumar@gmail.com"),
                  onTap: () => Navigator.pop(context, "nithish.kumar@gmail.com"),
                ),
                const Divider(),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppPalette.secondary,
                    child: Text("GU", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: const Text("Guest User", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text("guest.taxi@gmail.com"),
                  onTap: () => Navigator.pop(context, "guest.taxi@gmail.com"),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedEmail == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppPalette.primary),
                SizedBox(width: 18),
                Text(
                  "Connecting to Google...",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    Navigator.pop(context); // Close connecting dialog

    final mockPhone = selectedEmail;
    final mockName = selectedEmail.split("@").first
        .replaceAll(RegExp(r'[._-]'), ' ')
        .split(' ')
        .map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '')
        .join(' ') + " (Google)";
    const mockPassword = "google-sign-in-password-auth";

    try {
      Map<String, dynamic> loginResponse;
      String actualRole = isDriver ? "driver" : "user";

      try {
        loginResponse = await ApiService.login(
          mockPhone,
          mockPassword,
          role: isDriver ? "driver" : "user",
        );
        actualRole = loginResponse["role"]?.toString() ?? actualRole;
      } catch (loginErr) {
        final errStr = loginErr.toString();
        if (errStr.contains("User not found")) {
          await ApiService.register(
            mockName,
            mockPhone,
            mockPassword,
            role: isDriver ? "driver" : "user",
          );
          loginResponse = await ApiService.login(
            mockPhone,
            mockPassword,
            role: isDriver ? "driver" : "user",
          );
          actualRole = loginResponse["role"]?.toString() ?? actualRole;
        } else if (errStr.contains("This account is not a driver account")) {
          loginResponse = await ApiService.login(
            mockPhone,
            mockPassword,
            role: "user",
          );
          actualRole = "user";
        } else {
          rethrow;
        }
      }

      if (loginResponse["message"] == "Login successful" &&
          loginResponse["token"] != null &&
          loginResponse["userId"] != null) {
        ApiService.token = loginResponse["token"];
        SessionService.saveSession(
          loginResponse["token"],
          loginResponse["userId"],
          actualRole,
          name: loginResponse["name"]?.toString(),
          phone: loginResponse["phone"]?.toString(),
        );
        if (!mounted) return;

        if (actualRole == "driver") {
          try {
            await ApiService.toggleDriver(loginResponse["userId"], isAvailable: true);
          } catch (e) {
            print("Auto-set online error: $e");
          }
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DriverScreen(driverId: loginResponse["userId"]),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(userId: loginResponse["userId"]),
            ),
          );
        }
      } else {
        setState(() {
          message = loginResponse["message"] ?? "Google Login failed";
        });
      }
    } catch (e) {
      print("GOOGLE AUTH ERROR: $e");
      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
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
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const RevealMotion(
                      delay: Duration(milliseconds: 40),
                      beginOffset: Offset(0, -0.1),
                      child: ReflectiveBanner(
                        colors: const [AppPalette.primary, AppPalette.secondary],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.person_add_alt_1_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                            SizedBox(height: 14),
                            Text(
                              "Join The Fleet",
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "Create your account and unlock smooth city rides with real-time control.",
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
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
                              "Create Account",
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.2,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Set up your profile and start booking in seconds.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
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
                              controller: nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: "Name",
                                hintText: "Enter full name",
                                prefixIcon: Icon(Icons.person_rounded),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: "Phone",
                                hintText: "Enter mobile number",
                                prefixIcon: Icon(Icons.phone_rounded),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: passwordController,
                              obscureText: obscurePassword,
                              decoration: InputDecoration(
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
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                "Already have an account? Login",
                              ),
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
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 54),
                                side: BorderSide(color: AppPalette.slate300.withOpacity(0.7)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              onPressed: isLoading ? null : loginWithGoogle,
                              icon: Image.network(
                                "https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Google_%22G%22_Logo.svg/512px-Google_%22G%22_Logo.svg.png",
                                height: 22,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.account_circle_rounded,
                                  color: AppPalette.primary,
                                  size: 22,
                                ),
                              ),
                              label: const Text(
                                "Continue with Google",
                                style: TextStyle(
                                  color: AppPalette.slate900,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),

                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              child: message.isEmpty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.1),
                                          ),
                                        ),
                                        child: Text(
                                          message,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 14,
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

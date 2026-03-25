import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'register_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String result = "";
  bool isLoading = false;

  void loginUser() async {
    if (phoneController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      setState(() {
        result = "Please enter phone and password";
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
        phoneController.text.trim(),
        passwordController.text.trim(),
      );

      print("LOGIN RESPONSE: $response");

      if (response["message"] == "Login successful" &&
          response["userId"] != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomeScreen(
              userId: response["userId"],
            ),
          ),
        );
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

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bike Taxi Login"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: "Phone",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: "Password",
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : loginUser,
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Login"),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegisterScreen(),
                  ),
                );
              },
              child: const Text("Create Account"),
            ),
            const SizedBox(height: 20),
            Text(
              result,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
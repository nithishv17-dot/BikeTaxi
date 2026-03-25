import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'services/socket_service.dart';
void main() {

  SocketService.connect();

  runApp(const BikeTaxiApp());
}
class BikeTaxiApp extends StatelessWidget {
  const BikeTaxiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(),
    );
  }
}
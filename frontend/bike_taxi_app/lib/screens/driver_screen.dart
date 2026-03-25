import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'driver_screen.dart';

class DriverScreen extends StatefulWidget {
  final String driverId;

  const DriverScreen({super.key, required this.driverId});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  bool isAvailable = false;
  String message = "";

  void toggleDriver() async {
    try {
      final response = await ApiService.toggleDriver(widget.driverId);

      setState(() {
        isAvailable = response["isAvailable"];
        message = response["message"];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Panel"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "Driver Status: ${isAvailable ? "ONLINE" : "OFFLINE"}",
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: toggleDriver,
              child: const Text("Toggle Availability"),
            ),
            ElevatedButton(
                            onPressed: () {
                                Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => DriverScreen(
                                    driverId: userId, // ⚠️ for testing you can pass same ID
                                    ),
                                ),
                                );
                            },
                            child: const Text("Driver Panel"),
                            ),
            const SizedBox(height: 20),
            Text(message),
          ],
        ),
      ),
    );
  }
}
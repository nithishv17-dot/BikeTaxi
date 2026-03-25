import 'package:flutter/material.dart';
import 'request_ride_screen.dart';
import 'ride_history_screen.dart';
import 'driver_list_screen.dart';
class HomeScreen extends StatelessWidget {
  final String userId;

  const HomeScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bike Taxi Home"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Welcome to Bike Taxi",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RequestRideScreen(userId: userId),
                  ),
                );
              },
              child: const Text("Request Ride"),
            ),

            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RideHistoryScreen(userId: userId),
                  ),
                );
              },
              child: const Text("Ride History"),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DriverListScreen(),
                  ),
                );
              },
              child: const Text("View Drivers"),
            ),
            
          ],
          
        ),
      ),
    );
  }
}
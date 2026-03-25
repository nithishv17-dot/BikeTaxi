import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'ride_status_screen.dart';

class RequestRideScreen extends StatefulWidget {
  final String userId;

  const RequestRideScreen({super.key, required this.userId});

  @override
  State<RequestRideScreen> createState() => _RequestRideScreenState();
}

class _RequestRideScreenState extends State<RequestRideScreen> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();

  String message = "";
  bool isLoading = false;

  void requestRide() async {
    if (pickupController.text.trim().isEmpty ||
        destinationController.text.trim().isEmpty) {
      setState(() {
        message = "Please enter pickup and destination";
      });
      return;
    }

    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.requestRide(
        widget.userId,
        pickupController.text.trim(),
        destinationController.text.trim(),
      );

      setState(() {
        message = response["message"] ?? "Ride requested successfully";
      });

      if (response["ride"] != null && response["ride"]["_id"] != null) {
        final String rideId = response["ride"]["_id"];

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => RideStatusScreen(rideId: rideId),
          ),
        );
      }
    } catch (e) {
      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    pickupController.dispose();
    destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Request Ride"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: pickupController,
              decoration: const InputDecoration(
                labelText: "Pickup Location",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: destinationController,
              decoration: const InputDecoration(
                labelText: "Destination",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : requestRide,
              child: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Request Ride"),
            ),
            const SizedBox(height: 20),
            Text(message),
          ],
        ),
      ),
    );
  }
}
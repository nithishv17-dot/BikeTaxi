import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RideHistoryScreen extends StatefulWidget {
  final String userId;

  const RideHistoryScreen({super.key, required this.userId});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  List<dynamic> rides = [];
  String message = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchRideHistory();
  }

  Future<void> fetchRideHistory() async {
    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.getUserRideHistory(widget.userId);

      setState(() {
        rides = response["rides"] ?? [];
        message = response["message"] ?? "";
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
        isLoading = false;
      });
    }
  }

  Widget buildRideCard(Map<String, dynamic> ride) {
    final pickup = ride["pickup"]?.toString() ?? "";
    final destination = ride["destination"]?.toString() ?? "";
    final status = ride["status"]?.toString() ?? "";
    final createdAt = ride["createdAt"]?.toString() ?? "";

    String driverName = "Not assigned";
    String driverPhone = "N/A";

    final driver = ride["driverId"];
    if (driver is Map<String, dynamic>) {
      driverName = driver["name"]?.toString() ?? "Not assigned";
      driverPhone = driver["phone"]?.toString() ?? "N/A";
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Pickup: $pickup"),
            const SizedBox(height: 6),
            Text("Destination: $destination"),
            const SizedBox(height: 6),
            Text("Status: $status"),
            const SizedBox(height: 6),
            Text("Driver: $driverName"),
            const SizedBox(height: 6),
            Text("Driver Phone: $driverPhone"),
            const SizedBox(height: 6),
            Text("Created At: $createdAt"),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ride History"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : rides.isEmpty
                ? Center(
                    child: Text(
                      message.isNotEmpty ? message : "No rides found",
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: fetchRideHistory,
                    child: ListView(
                      children: [
                        ...rides.map((ride) => buildRideCard(ride)).toList(),
                      ],
                    ),
                  ),
      ),
    );
  }
}
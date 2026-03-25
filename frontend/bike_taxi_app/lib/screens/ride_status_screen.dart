import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RideStatusScreen extends StatefulWidget {
  final String rideId;

  const RideStatusScreen({super.key, required this.rideId});

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen> {
  Map<String, dynamic>? ride;
  String message = "";
  bool isLoading = true;
  bool actionLoading = false;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();
    fetchRide();

    refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      fetchRide();
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchRide() async {
    try {
      final response = await ApiService.getRide(widget.rideId);

      if (!mounted) return;

      setState(() {
        ride = response["ride"];
        message = response["message"] ?? "";
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
        isLoading = false;
      });
    }
  }

  Future<void> startRide() async {
    setState(() {
      actionLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.startRide(widget.rideId);

      if (!mounted) return;

      setState(() {
        message = response["message"] ?? "Ride started successfully";
      });

      await fetchRide();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (!mounted) return;

      setState(() {
        actionLoading = false;
      });
    }
  }

  Future<void> completeRide() async {
    setState(() {
      actionLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.completeRide(widget.rideId);

      if (!mounted) return;

      setState(() {
        message = response["message"] ?? "Ride completed successfully";
      });

      await fetchRide();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (!mounted) return;

      setState(() {
        actionLoading = false;
      });
    }
  }

  Future<void> cancelRide() async {
    setState(() {
      actionLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.cancelRide(widget.rideId);

      if (!mounted) return;

      setState(() {
        message = response["message"] ?? "Ride cancelled successfully";
      });

      await fetchRide();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (!mounted) return;

      setState(() {
        actionLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ride?["status"]?.toString() ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Ride Status"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Ride ID: ${widget.rideId}"),
                  const SizedBox(height: 10),
                  Text("Pickup: ${ride?["pickup"] ?? ""}"),
                  const SizedBox(height: 8),
                  Text("Destination: ${ride?["destination"] ?? ""}"),
                  const SizedBox(height: 8),
                  Text("Status: $status"),
                  const SizedBox(height: 10),
                  Text("Driver: ${ride?["driverId"]?["name"] ?? "N/A"}"),
                  const SizedBox(height: 5),
                  Text("Phone: ${ride?["driverId"]?["phone"] ?? "N/A"}"),
                  const SizedBox(height: 20),
                  if (status == "accepted")
                    ElevatedButton(
                      onPressed: actionLoading ? null : startRide,
                      child: const Text("Start Ride"),
                    ),
                  if (status == "ongoing") ...[
                    ElevatedButton(
                      onPressed: actionLoading ? null : completeRide,
                      child: const Text("Complete Ride"),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (status == "accepted" || status == "ongoing")
                    ElevatedButton(
                      onPressed: actionLoading ? null : cancelRide,
                      child: const Text("Cancel Ride"),
                    ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: fetchRide,
                    child: const Text("Refresh Status"),
                  ),
                  const SizedBox(height: 20),
                  Text(message),
                ],
              ),
      ),
    );
  }
}
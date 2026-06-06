import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';
import 'driver_negotiation_screen.dart';
import 'ride_status_screen.dart';

class DriverScreen extends StatefulWidget {
  final String driverId;

  const DriverScreen({super.key, required this.driverId});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final TextEditingController rideIdController = TextEditingController();
  final Map<String, TextEditingController> otpControllers = {};

  bool isAvailable = false;
  bool isLoading = true;
  String message = "";
  List<Map<String, dynamic>> directRequests = [];

  TextEditingController _otpControllerForRide(String rideId) {
    return otpControllers.putIfAbsent(rideId, TextEditingController.new);
  }

  @override
  void initState() {
    super.initState();
    _loadDriverStatus();
    SocketService.listenRideRequested((_) => _loadDriverStatus());
  }

  Future<void> _loadDriverStatus() async {
    try {
      final response = await ApiService.getDrivers();
      final drivers = List<Map<String, dynamic>>.from(
        (response["drivers"] as List<dynamic>? ?? const []).whereType<Map>(),
      );
      final driver = drivers.firstWhere(
        (item) => item["_id"]?.toString() == widget.driverId,
        orElse: () => <String, dynamic>{},
      );

      final requestsResponse = await ApiService.getDriverRequests(widget.driverId);
      final fetchedRequests = List<Map<String, dynamic>>.from(
        (requestsResponse["rides"] as List<dynamic>? ?? const []).whereType<Map>(),
      );

      if (!mounted) return;

      setState(() {
        isAvailable = driver["isAvailable"] ?? false;
        directRequests = fetchedRequests;
        isLoading = false;
        message = "Driver status loaded";
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        message = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  @override
  void dispose() {
    rideIdController.dispose();
    for (final controller in otpControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> acceptDirectRide(String rideId) async {
    setState(() {
      isLoading = true;
      message = "Accepting ride request...";
    });

    try {
      final response = await ApiService.acceptRide(rideId);

      if (!mounted) return;

      final successMessage = response["message"]?.toString() ??
          "Ride request accepted successfully";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );

      _loadDriverStatus();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RideStatusScreen(rideId: rideId, isDriver: true),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      final errorMessage = e.toString().replaceFirst("Exception: ", "");

      setState(() {
        message = errorMessage;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> toggleDriver() async {
    setState(() {
      isLoading = true;
      message = "Updating availability...";
    });

    try {
      final response = await ApiService.toggleDriver(widget.driverId);

      if (!mounted) return;

      final nextStatus = response["isAvailable"] ?? !isAvailable;

      setState(() {
        isAvailable = nextStatus;
        message = nextStatus
            ? "You are now online and visible to riders."
            : "You are now offline and not accepting rides.";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      await _loadDriverStatus();
    } catch (e) {
      if (!mounted) return;

      final errorMessage = e.toString().replaceFirst("Exception: ", "");

      setState(() {
        message = errorMessage;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _buildRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Incoming Ride Requests",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.slate900,
              ),
            ),
            if (directRequests.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${directRequests.length} ACTIVE",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (directRequests.isEmpty)
          const ReflectionCard(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.directions_bike_rounded, color: AppPalette.slate300, size: 48),
                  SizedBox(height: 12),
                  Text(
                    "No Active Ride Requests",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppPalette.slate700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "You will see passenger requests here when they book.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppPalette.slate500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...directRequests.asMap().entries.map((entry) {
            final index = entry.key;
            final ride = entry.value;
            final rideId = ride["_id"]?.toString() ?? "";
            final riderName = ride["userId"]?["name"] ?? "Passenger";
            final riderPhone = ride["userId"]?["phone"] ?? "N/A";
            final pickup = ride["pickupAddress"] ?? ride["pickup"] ?? "";
            final drop = ride["dropAddress"] ?? ride["destination"] ?? "";
            final fare = ride["estimatedFare"] ?? 0;
            final otpController = _otpControllerForRide(rideId);

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: RevealMotion(
                delay: Duration(milliseconds: 100 + index * 50),
                child: ReflectionCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppPalette.primary.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              color: AppPalette.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  riderName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppPalette.slate900,
                                  ),
                                ),
                                Text(
                                  "Phone: $riderPhone",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.slate500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "Rs. $fare",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppPalette.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded, color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pickup,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppPalette.slate700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              drop,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppPalette.slate700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24, thickness: 1),
                      ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () => acceptDirectRide(rideId),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text("Accept & Navigate"),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Captain Panel"),
        actions: [
          IconButton(
            onPressed: _loadDriverStatus,
            tooltip: "Refresh Status",
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumBackdrop(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadDriverStatus,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                // Top Banner
                RevealMotion(
                  delay: const Duration(milliseconds: 40),
                  beginOffset: const Offset(0, -0.1),
                  child: ReflectiveBanner(
                    colors: const [AppPalette.primary, AppPalette.textPrimary],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Driver Hub",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Welcome back, Captain",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: isAvailable ? AppPalette.secondary : const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isAvailable ? AppPalette.secondary : const Color(0xFFEF4444)).withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isAvailable ? "You are Online & Accepting Rides" : "You are Offline",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Status Toggle Card
                RevealMotion(
                  delay: const Duration(milliseconds: 160),
                  child: ReflectionCard(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Duty Status",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: AppPalette.slate900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isAvailable ? "Go offline to take a break" : "Go online to receive rides",
                                    style: const TextStyle(
                                      color: AppPalette.slate500,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: isAvailable,
                              onChanged: isLoading ? null : (_) => toggleDriver(),
                              activeTrackColor: AppPalette.secondary,
                              activeColor: Colors.white,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Negotiation Board Action Card
                RevealMotion(
                  delay: const Duration(milliseconds: 280),
                  child: ReflectionCard(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DriverNegotiationScreen(driverId: widget.driverId),
                        ),
                      );
                    },
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C3AED).withOpacity(0.14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.handshake_rounded, color: Color(0xFF7C3AED), size: 28),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Negotiation Board",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.slate900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Respond to passenger fare counter-offers.",
                                style: TextStyle(
                                  color: AppPalette.slate500,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 16,
                          color: AppPalette.slate500,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildRequestsSection(),
                
                // Status Message Box (if present)
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  RevealMotion(
                    delay: Duration.zero,
                    child: ReflectionCard(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      tintColor: const Color(0xFFEFF6FF),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: AppPalette.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppPalette.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

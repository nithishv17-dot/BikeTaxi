import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/premium_ui.dart';

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

  Color _badgeColor(String value) {
    switch (value.toLowerCase()) {
      case "completed":
      case "paid":
      case "accepted":
        return AppPalette.secondary;
      case "ongoing":
      case "countered":
        return AppPalette.primary;
      case "cancelled":
      case "rejected":
        return const Color(0xFFDC2626);
      default:
        return AppPalette.accent;
    }
  }

  Widget _buildBadge(String text) {
    final color = _badgeColor(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget buildRideCard(Map<String, dynamic> ride) {
    final pickup =
        ride["pickupAddress"]?.toString() ?? ride["pickup"]?.toString() ?? "";
    final destination =
        ride["dropAddress"]?.toString() ??
        ride["destination"]?.toString() ??
        "";
    final pickupCoords =
        "${ride["pickupLat"] ?? "N/A"}, ${ride["pickupLng"] ?? "N/A"}";
    final dropCoords =
        "${ride["dropLat"] ?? ride["destinationLat"] ?? "N/A"}, ${ride["dropLng"] ?? ride["destinationLng"] ?? "N/A"}";
    final status = ride["status"]?.toString() ?? "";
    final initialFare = ride["initialFare"]?.toString() ?? "N/A";
    final offeredFare = ride["offeredFare"]?.toString() ?? "N/A";
    final negotiationStatus = ride["negotiationStatus"]?.toString() ?? "N/A";
    final paymentMethod = ride["paymentMethod"]?.toString() ?? "N/A";
    final paymentStatus = ride["paymentStatus"]?.toString() ?? "N/A";
    final createdAt = ride["createdAt"]?.toString() ?? "";

    String driverName = "Not assigned";
    String driverPhone = "N/A";

    final driver = ride["driverId"];
    if (driver is Map<String, dynamic>) {
      driverName = driver["name"]?.toString() ?? "Not assigned";
      driverPhone = driver["phone"]?.toString() ?? "N/A";
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ReflectionCard(
        padding: const EdgeInsets.all(18),
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Ride Summary",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.slate900,
                  ),
                ),
                _buildBadge(status),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              pickup,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppPalette.slate900,
              ),
            ),
            const SizedBox(height: 4),
            const Icon(
              Icons.arrow_downward_rounded,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 4),
            Text(
              destination,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppPalette.slate900,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildBadge(paymentStatus),
                _buildBadge(negotiationStatus),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFDBEAFE).withOpacity(0.4),
                    Colors.white.withOpacity(0.75),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFBFDBFE).withOpacity(0.55),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Initial Fare: $initialFare"),
                  const SizedBox(height: 6),
                  Text("Offered Fare: $offeredFare"),
                  const SizedBox(height: 6),
                  Text("Payment Method: $paymentMethod"),
                  const SizedBox(height: 6),
                  Text("Pickup Coords: $pickupCoords"),
                  const SizedBox(height: 6),
                  Text("Drop Coords: $dropCoords"),
                  const SizedBox(height: 6),
                  Text("Driver: $driverName"),
                  const SizedBox(height: 6),
                  Text("Driver Phone: $driverPhone"),
                  const SizedBox(height: 6),
                  Text("Created At: $createdAt"),
                ],
              ),
            ),
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
        actions: [
          IconButton(
            tooltip: "Refresh",
            onPressed: fetchRideHistory,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumBackdrop(
        accentColor: AppPalette.primary,
        secondaryColor: AppPalette.secondary,
        child: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: fetchRideHistory,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      const RevealMotion(
                        delay: Duration(milliseconds: 40),
                        beginOffset: Offset(0, -0.1),
                        child: ReflectiveBanner(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Trip Analytics",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Every ride. Every fare.\nOne premium timeline.",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (rides.isEmpty)
                        ReflectionCard(
                          borderRadius: BorderRadius.circular(20),
                          child: Text(
                            message.isNotEmpty ? message : "No rides found",
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppPalette.slate600,
                            ),
                          ),
                        )
                      else
                        ...rides.map((ride) => buildRideCard(ride)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

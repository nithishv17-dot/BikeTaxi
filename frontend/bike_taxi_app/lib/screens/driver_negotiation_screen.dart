import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';
import 'ride_status_screen.dart';

class DriverNegotiationScreen extends StatefulWidget {
  final String driverId;

  const DriverNegotiationScreen({super.key, required this.driverId});

  @override
  State<DriverNegotiationScreen> createState() =>
      _DriverNegotiationScreenState();
}

class _DriverNegotiationScreenState extends State<DriverNegotiationScreen> {
  bool isLoading = true;
  bool isSubmitting = false;
  String message = "";
  final Map<String, TextEditingController> offerControllers = {};
  List<Map<String, dynamic>> rides = [];

  @override
  void initState() {
    super.initState();
    fetchNegotiationRides();
    SocketService.listenNegotiationRideRequested(
      (_) => fetchNegotiationRides(),
    );
    SocketService.listenNegotiationClosed((_) => fetchNegotiationRides());
    SocketService.listenNegotiationExpired((_) => fetchNegotiationRides());

    SocketService.listenNegotiationOfferAcceptedByUser((data) {
      _handleDriverAssignedSocket(data);
    });
    SocketService.listenRideStarted((data) {
      _handleDriverAssignedSocket(data);
    });
  }

  void _handleDriverAssignedSocket(dynamic data) {
    if (data == null || !mounted) return;
    final rideId = _normalizeId(data["_id"]);
    final assignedDriverId = _normalizeId(data["driverId"]);

    if (assignedDriverId == widget.driverId && rideId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ride matched! Opening status page...")),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RideStatusScreen(rideId: rideId, isDriver: true),
        ),
      );
    } else {
      fetchNegotiationRides();
    }
  }

  String? _normalizeId(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    if (value is Map) {
      return value["\$oid"]?.toString() ??
          value["id"]?.toString() ??
          value["_id"]?.toString();
    }
    return value.toString();
  }

  @override
  void dispose() {
    for (final controller in offerControllers.values) {
      controller.dispose();
    }
    SocketService.removeAllRideListeners();
    super.dispose();
  }

  TextEditingController _controllerForRide(String rideId) {
    return offerControllers.putIfAbsent(rideId, TextEditingController.new);
  }

  Future<void> fetchNegotiationRides() async {
    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.getDriverNegotiationRides(
        widget.driverId,
      );

      if (!mounted) return;

      setState(() {
        rides = (response["rides"] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((ride) => Map<String, dynamic>.from(ride))
            .toList();
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

  Future<void> submitOffer(String rideId, {bool acceptBaseFare = false}) async {
    final controller = _controllerForRide(rideId);
    final offeredFare = double.tryParse(controller.text.trim());

    if (!acceptBaseFare && offeredFare == null) {
      setState(() {
        message = "Enter a valid offer amount";
      });
      return;
    }

    setState(() {
      isSubmitting = true;
      message = acceptBaseFare
          ? "Submitting base-fare acceptance..."
          : "Submitting offer...";
    });

    try {
      final response = await ApiService.submitRideOffer(
        rideId,
        widget.driverId,
        offeredFare: offeredFare,
        acceptBaseFare: acceptBaseFare,
      );

      if (!mounted) return;

      final responseMessage = response["message"]?.toString() ??
          (acceptBaseFare
              ? "Base fare accepted successfully"
              : "Offer submitted successfully");

      setState(() {
        message = responseMessage;
        controller.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(responseMessage)),
      );

      await fetchNegotiationRides();
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
          isSubmitting = false;
        });
      }
    }
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final rideId = ride["_id"]?.toString() ?? "";
    final controller = _controllerForRide(rideId);

    final offers = (ride["offers"] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((offer) => Map<String, dynamic>.from(offer))
        .toList();

    final existingOffer = offers.firstWhere(
      (offer) => offer["driverId"]?.toString() == widget.driverId,
      orElse: () => <String, dynamic>{},
    );

    final hasPendingOffer = existingOffer.isNotEmpty &&
        (existingOffer["status"] == "pending" ||
            existingOffer["status"] == "accepted_base");

    return ReflectionCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Negotiation Trip",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.slate900,
                  letterSpacing: -0.3,
                ),
              ),
              if (hasPendingOffer)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.sky500.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "PENDING",
                    style: TextStyle(
                      color: AppPalette.sky500,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Route Details
          Row(
            children: [
              const Icon(Icons.circle_outlined, size: 14, color: AppPalette.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ride["pickupAddress"] ?? ride["pickup"] ?? "N/A",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppPalette.slate900,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: SizedBox(
              height: 14,
              child: VerticalDivider(thickness: 1.5, width: 2, color: AppPalette.slate500),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFFEF4444)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ride["dropAddress"] ?? ride["destination"] ?? "N/A",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppPalette.slate900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            "Estimated Fare: Rs. ${ride["estimatedFare"] ?? 0}",
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppPalette.slate900,
            ),
          ),
          if (hasPendingOffer) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, color: Color(0xFF2563EB), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      existingOffer["status"] == "accepted_base"
                          ? "You accepted the base fare (Rs. ${ride["estimatedFare"]}). Waiting for rider response."
                          : "You countered with Rs. ${existingOffer["offeredFare"]}. Waiting for rider response.",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E40AF),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: "Your Offer Amount",
                hintText: "Enter custom offer in Rs.",
                prefixIcon: Icon(Icons.sell_rounded),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (rideId.isEmpty || isSubmitting)
                        ? null
                        : () => submitOffer(rideId),
                    child: Text(isSubmitting ? "Sending..." : "Send Offer"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: (rideId.isEmpty || isSubmitting)
                        ? null
                        : () => submitOffer(rideId, acceptBaseFare: true),
                    child: Text(
                      isSubmitting ? "Processing..." : "Accept Base",
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Negotiation Board"),
        actions: [
          IconButton(
            tooltip: "Refresh List",
            onPressed: fetchNegotiationRides,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: PremiumBackdrop(
        child: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: fetchNegotiationRides,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      // Banner Card
                      const RevealMotion(
                        delay: Duration(milliseconds: 40),
                        beginOffset: Offset(0, -0.1),
                        child: ReflectiveBanner(
                          colors: const [AppPalette.primary, Color(0xFF7C3AED)],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Live Counters",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "Negotiate Trip Fares\nIn Real-Time.",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Status / Error message
                      if (message.isNotEmpty) ...[
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
                        const SizedBox(height: 16),
                      ],

                      // Rides list
                      if (rides.isEmpty)
                        RevealMotion(
                          delay: const Duration(milliseconds: 140),
                          child: ReflectionCard(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.no_accounts_rounded,
                                    size: 48,
                                    color: AppPalette.slate500.withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    "No active negotiation requests.",
                                    style: TextStyle(
                                      color: AppPalette.slate900,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    "Pull down or click refresh to scan again.",
                                    style: TextStyle(
                                      color: AppPalette.slate500,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        ...rides.asMap().entries.map((entry) {
                          final index = entry.key;
                          final ride = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: RevealMotion(
                              delay: Duration(milliseconds: 160 + index * 60),
                              child: _buildRideCard(ride),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';
import '../utils/location_display.dart';
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
          builder: (context) =>
              RideStatusScreen(rideId: rideId, isDriver: true),
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

      final responseMessage =
          response["message"]?.toString() ??
          (acceptBaseFare
              ? "Base fare accepted successfully"
              : "Offer submitted successfully");

      setState(() {
        message = responseMessage;
        controller.clear();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(responseMessage)));

      await fetchNegotiationRides();
    } catch (e) {
      if (!mounted) return;

      final errorMessage = e.toString().replaceFirst("Exception: ", "");

      setState(() {
        message = errorMessage;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  Future<void> declineRide(String rideId) async {
    setState(() {
      isSubmitting = true;
      message = "Declining trip...";
    });

    try {
      await ApiService.rejectFare(rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Trip declined successfully")),
      );
      await fetchNegotiationRides();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Decline failed: ${e.toString()}")),
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

    String formatFareToInt(dynamic rawFare) {
      if (rawFare == null) return "0.00";
      final parsed = double.tryParse(rawFare.toString());
      if (parsed == null) {
        if (rawFare.toString() == "N/A") return "N/A";
        return rawFare.toString();
      }
      return parsed.round().toStringAsFixed(2);
    }

    final offers = (ride["offers"] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((offer) => Map<String, dynamic>.from(offer))
        .toList();

    final existingOffer = offers.firstWhere(
      (offer) => offer["driverId"]?.toString() == widget.driverId,
      orElse: () => <String, dynamic>{},
    );

    final hasPendingOffer =
        existingOffer.isNotEmpty &&
        (existingOffer["status"] == "pending" ||
            existingOffer["status"] == "accepted_base");

    if (controller.text.isEmpty) {
      final initialVal = existingOffer.isNotEmpty
          ? existingOffer["offeredFare"]
          : ride["estimatedFare"];
      if (initialVal != null) {
        controller.text = initialVal.toString();
      }
    }

    return ReflectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Negotiation Board",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (hasPendingOffer ? AppPalette.sky500 : const Color(0xFF16A34A)).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hasPendingOffer ? "PENDING" : "IN PROGRESS",
                  style: TextStyle(
                    color: hasPendingOffer ? AppPalette.sky500 : const Color(0xFF4ADE80),
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          // Passenger details + Counter inputs
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.people_alt_rounded,
                  color: AppPalette.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "New Counter-Offer",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Passenger: ${ride["userId"]?["name"] ?? "Passenger"}",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Rs. ",
                        style: TextStyle(
                          color: AppPalette.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: AppPalette.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppPalette.primary),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppPalette.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Baseline: Rs. ${formatFareToInt(ride["estimatedFare"])}",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.4),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Collapsible Route Details
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                "View Route Details",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.55),
                  fontWeight: FontWeight.w600,
                ),
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.circle_outlined,
                      size: 12,
                      color: AppPalette.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        readableLocationLabel(
                          ride["pickupAddress"]?.toString() ??
                              ride["pickup"]?.toString(),
                          fallback: "Pickup address",
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.slate900,
                        ),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 5),
                  child: SizedBox(
                    height: 10,
                    child: VerticalDivider(
                      thickness: 1.5,
                      width: 2,
                      color: AppPalette.slate500,
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 12,
                      color: Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        readableLocationLabel(
                          ride["dropAddress"]?.toString() ??
                              ride["destination"]?.toString(),
                          fallback: "Drop address",
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.slate900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: isSubmitting ? null : () => declineRide(rideId),
                  child: const Text(
                    "Decline",
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, val, child) {
                    final valString = val.text.trim();
                    final valDouble = double.tryParse(valString);
                    final baseline = double.tryParse(ride["estimatedFare"]?.toString() ?? "") ?? 0.0;

                    String labelText = "Accept Offer";
                    bool isCounter = false;

                    if (hasPendingOffer) {
                      labelText = "Update Counter";
                      isCounter = true;
                    } else if (valDouble != null && (valDouble - baseline).abs() > 0.01) {
                      labelText = "Send Counter";
                      isCounter = true;
                    }

                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: const Color(0xFFFFB77D),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: (rideId.isEmpty || isSubmitting)
                          ? null
                          : () {
                              if (isCounter) {
                                submitOffer(rideId);
                              } else {
                                submitOffer(rideId, acceptBaseFare: true);
                              }
                            },
                      child: Text(
                        isSubmitting ? "Sending..." : labelText,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Negotiation Board"),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            tintColor: const Color(0xFFEFF6FF),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  color: AppPalette.primary,
                                ),
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

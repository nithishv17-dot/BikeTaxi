import 'dart:async';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/session_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';
import '../utils/location_display.dart';
import 'driver_negotiation_screen.dart';
import 'ride_status_screen.dart';
import 'login_screen.dart';

class DriverScreen extends StatefulWidget {
  final String driverId;

  const DriverScreen({super.key, required this.driverId});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final TextEditingController rideIdController = TextEditingController();
  final Map<String, TextEditingController> otpControllers = {};
  final Map<String, TextEditingController> offerControllers = {};

  int _currentIndex = 0;
  String driverName = "";
  String driverPhone = "";

  bool isAvailable = false;
  bool isLoading = true;
  bool isSubmitting = false;
  String message = "";
  List<Map<String, dynamic>> directRequests = [];
  List<Map<String, dynamic>> negotiationRides = [];
  Timer? _locationTimer;

  void _startLocationUpdates() {
    _locationTimer?.cancel();
    if (isAvailable) {
      _updateLocation();
      _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted && isAvailable) {
          _updateLocation();
        }
      });
    }
  }

  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _updateLocation() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (pos != null) {
        await ApiService.updateLocation(pos['lat']!, pos['lng']!);
        print("Driver location updated: ${pos['lat']}, ${pos['lng']}");
      }
    } catch (e) {
      print("Error updating driver location: $e");
    }
  }

  TextEditingController _otpControllerForRide(String rideId) {
    return otpControllers.putIfAbsent(rideId, TextEditingController.new);
  }

  TextEditingController _offerControllerForRide(String rideId) {
    return offerControllers.putIfAbsent(rideId, TextEditingController.new);
  }

  Future<void> submitOffer(String rideId, {bool acceptBaseFare = false}) async {
    final controller = _offerControllerForRide(rideId);
    final offeredFare = double.tryParse(controller.text.trim());

    if (!acceptBaseFare && offeredFare == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid offer amount")),
      );
      return;
    }

    setState(() {
      isSubmitting = true;
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
        controller.clear();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(responseMessage)));

      await _loadDriverStatus();
    } catch (e) {
      if (!mounted) return;
      final errorMessage = e.toString().replaceFirst("Exception: ", "");
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
    });

    try {
      await ApiService.rejectFare(rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Trip declined successfully")),
      );
      await _loadDriverStatus();
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
      _loadDriverStatus();
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
  void initState() {
    super.initState();
    final session = SessionService.loadSession();
    if (session != null) {
      driverName = session["name"] ?? "";
      driverPhone = session["phone"] ?? "";
    }
    _loadDriverStatus();
    SocketService.listenRideRequested((_) => _loadDriverStatus());
    SocketService.listenRideAccepted((_) => _loadDriverStatus());
    SocketService.listenRideStarted((_) => _loadDriverStatus());
    SocketService.listenRideCompleted((_) => _loadDriverStatus());
    SocketService.listenRideCancelled((_) => _loadDriverStatus());
    SocketService.listenNegotiationClosed((_) => _loadDriverStatus());
    SocketService.listenNegotiationRideRequested((_) => _loadDriverStatus());
    SocketService.listenNegotiationOfferAcceptedByUser((data) => _handleDriverAssignedSocket(data));
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

      final requestsResponse = await ApiService.getDriverRequests(
        widget.driverId,
      );
      final fetchedRequests = List<Map<String, dynamic>>.from(
        (requestsResponse["rides"] as List<dynamic>? ?? const [])
            .whereType<Map>(),
      );

      final negotiationResponse = await ApiService.getDriverNegotiationRides(
        widget.driverId,
      );
      final fetchedNegotiations = List<Map<String, dynamic>>.from(
        (negotiationResponse["rides"] as List<dynamic>? ?? const [])
            .whereType<Map>(),
      );

      if (!mounted) return;

      setState(() {
        isAvailable = driver["isAvailable"] ?? false;
        driverName = driver["name"] ?? driverName;
        driverPhone = driver["phone"] ?? driverPhone;
        directRequests = fetchedRequests;
        negotiationRides = fetchedNegotiations;
        isLoading = false;
        message = "Driver status loaded";
      });
      _startLocationUpdates();
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
    _stopLocationUpdates();
    SocketService.removeAllRideListeners();
    rideIdController.dispose();
    for (final controller in otpControllers.values) {
      controller.dispose();
    }
    for (final controller in offerControllers.values) {
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

      final successMessage =
          response["message"]?.toString() ??
          "Ride request accepted successfully";

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));

      _loadDriverStatus();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              RideStatusScreen(rideId: rideId, isDriver: true),
        ),
      );
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      await _loadDriverStatus();
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
                  Icon(
                    Icons.directions_bike_rounded,
                    color: AppPalette.slate300,
                    size: 48,
                  ),
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
                    style: TextStyle(color: AppPalette.slate500, fontSize: 13),
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
            final pickup = readableLocationLabel(
              ride["pickupAddress"]?.toString() ?? ride["pickup"]?.toString(),
              fallback: "Pickup address",
            );
            final drop = readableLocationLabel(
              ride["dropAddress"]?.toString() ??
                  ride["destination"]?.toString(),
              fallback: "Drop address",
            );
            final rawFare = ride["estimatedFare"];
            final fare = rawFare is num
                ? rawFare.round().toStringAsFixed(2)
                : (double.tryParse(rawFare?.toString() ?? "")?.round().toStringAsFixed(2) ?? "0.00");
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
                          const Icon(
                            Icons.location_on_rounded,
                            color: Colors.green,
                            size: 18,
                          ),
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
                          const Icon(
                            Icons.location_on_rounded,
                            color: Colors.red,
                            size: 18,
                          ),
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

  Widget _buildNegotiationBoardSection() {
    if (!isAvailable) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Negotiation Board",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.slate900,
              ),
            ),
            if (negotiationRides.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "${negotiationRides.length} ACTIVE",
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
        if (negotiationRides.isEmpty)
          const ReflectionCard(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.handshake_rounded,
                    color: AppPalette.slate300,
                    size: 48,
                  ),
                  SizedBox(height: 12),
                  Text(
                    "No Negotiation Offers",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppPalette.slate700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "You will see passenger counter-offers here when they request negotiations.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppPalette.slate500, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ...negotiationRides.map((ride) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildRideCard(ride),
              )),
      ],
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final rideId = ride["_id"]?.toString() ?? "";
    final controller = _offerControllerForRide(rideId);

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

  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: _loadDriverStatus,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          // Top Banner with integrated Duty Status switch
          RevealMotion(
            delay: const Duration(milliseconds: 40),
            beginOffset: const Offset(0, -0.1),
            child: ReflectiveBanner(
              colors: const [AppPalette.primary, AppPalette.textPrimary],
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isAvailable
                                    ? AppPalette.secondary
                                    : const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isAvailable
                                    ? "Online & Accepting Rides"
                                    : "You are Offline",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Duty Status",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Transform.scale(
                          scale: 0.85,
                          child: Switch(
                            value: isAvailable,
                            onChanged: isLoading ? null : (_) => toggleDriver(),
                            activeTrackColor: AppPalette.secondary,
                            activeColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Inline Negotiation Board Section
          _buildNegotiationBoardSection(),
          const SizedBox(height: 24),

          // Direct Incoming Requests Section
          _buildRequestsSection(),

          // Status Message Box (if present)
          if (message.isNotEmpty) ...[
            const SizedBox(height: 16),
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
          ],
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    final name = driverName.isNotEmpty ? driverName : "Captain";
    final phone = driverPhone.isNotEmpty ? driverPhone : "N/A";
    final initials = name
        .split(" ")
        .map((s) => s.isNotEmpty ? s[0] : "")
        .join()
        .toUpperCase();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          children: [
            RevealMotion(
              delay: const Duration(milliseconds: 60),
              child: ReflectionCard(
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 20,
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: AppPalette.primary,
                      child: Text(
                        initials.isNotEmpty ? initials : "C",
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.slate900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      phone != "N/A" ? "+91 $phone" : phone,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.slate500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        "CAPTAIN",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            RevealMotion(
              delay: const Duration(milliseconds: 140),
              child: ElevatedButton.icon(
                onPressed: () async {
                  setState(() {
                    isLoading = true;
                    message = "Logging out...";
                  });
                  try {
                    await ApiService.toggleDriver(
                      widget.driverId,
                      isAvailable: false,
                    );
                  } catch (e) {
                    print("Error setting driver offline on logout: $e");
                  }
                  SessionService.clearSession();
                  if (!mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.logout_rounded),
                label: const Text(
                  "Log Out",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
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
        title: Text(_currentIndex == 0 ? "Captain Panel" : "My Profile"),
        centerTitle: true,
      ),
      body: PremiumBackdrop(
        child: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: [_buildDashboardTab(), _buildProfileTab()],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ClipRRect(
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: Colors.white.withOpacity(0.94),
            indicatorColor: AppPalette.primary.withOpacity(0.12),
            height: 70,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_rounded, color: AppPalette.slate500),
                selectedIcon: Icon(
                  Icons.dashboard_rounded,
                  color: AppPalette.primary,
                ),
                label: "Dashboard",
              ),
              NavigationDestination(
                icon: Icon(Icons.person_rounded, color: AppPalette.slate500),
                selectedIcon: Icon(
                  Icons.person_rounded,
                  color: AppPalette.primary,
                ),
                label: "Profile",
              ),
            ],
          ),
        ),
      ),
    );
  }
}

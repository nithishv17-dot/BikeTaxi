import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';

class RideStatusScreen extends StatefulWidget {
  final String rideId;
  final bool isDriver;

  const RideStatusScreen({
    super.key,
    required this.rideId,
    this.isDriver = false,
  });

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen> {
  final TextEditingController otpController = TextEditingController();
  Map<String, dynamic>? ride;
  List<Map<String, dynamic>> offers = [];
  String message = "";
  bool isLoading = true;
  bool actionLoading = false;
  Timer? countdownTimer;
  int negotiationSecondsRemaining = 0;

  bool get isNegotiationRide =>
      ride?["bookingMode"]?.toString() == "negotiation";

  bool get isNegotiationWaiting =>
      isNegotiationRide && ride?["status"]?.toString() == "negotiating";

  bool get isNegotiationExpired =>
      isNegotiationRide && ride?["status"]?.toString() == "negotiation_expired";

  @override
  void initState() {
    super.initState();
    fetchRide();
    listenToRideEvents();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    SocketService.removeAllRideListeners();
    otpController.dispose();
    super.dispose();
  }

  void _syncCountdownFromRide() {
    countdownTimer?.cancel();
    negotiationSecondsRemaining = 0;

    if (!isNegotiationWaiting) {
      return;
    }

    final expiresAtRaw = ride?["negotiationExpiresAt"]?.toString();
    final expiresAt = expiresAtRaw == null
        ? null
        : DateTime.tryParse(expiresAtRaw)?.toLocal();

    if (expiresAt == null) {
      return;
    }

    void updateRemaining() {
      final remaining = expiresAt
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, 3600);

      if (!mounted) {
        return;
      }

      setState(() {
        negotiationSecondsRemaining = remaining;
      });

      if (remaining <= 0) {
        countdownTimer?.cancel();
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && ride?["status"]?.toString() == "negotiating") {
            fetchRide();
          }
        });
      }
    }

    updateRemaining();

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateRemaining();
    });
  }

  void _applyRide(Map<String, dynamic>? nextRide, {String? nextMessage}) {
    if (!mounted) {
      return;
    }

    setState(() {
      ride = nextRide;
      if (nextMessage != null) {
        message = nextMessage;
      }
      isLoading = false;
    });

    _syncCountdownFromRide();
  }

  String? _normalizeRideId(dynamic value) {
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

  String? _normalizeOfferId(dynamic value) {
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

  void listenToRideEvents() {
    void handleRideUpdate(dynamic data, String successMessage) {
      final rideId = _normalizeRideId(data?['_id']);

      if (!mounted || data == null || rideId != widget.rideId) {
        return;
      }

      final nextRide = Map<String, dynamic>.from(data as Map);
      _applyRide(nextRide, nextMessage: successMessage);
    }

    SocketService.listenRideRequested((data) {
      handleRideUpdate(data, "Ride requested successfully");
    });

    SocketService.listenRideAccepted((data) {
      handleRideUpdate(data, "Ride accepted successfully");
    });

    SocketService.listenRideStarted((data) {
      handleRideUpdate(data, "Ride started successfully");
    });

    SocketService.listenRideCompleted((data) {
      handleRideUpdate(data, "Ride completed successfully");
    });

    SocketService.listenRideCancelled((data) {
      handleRideUpdate(data, "Ride cancelled successfully");
    });

    SocketService.listenNegotiationOfferSubmitted((data) {
      final rideId = _normalizeRideId(data?["rideId"]);

      if (!mounted || data == null || rideId != widget.rideId) {
        return;
      }

      fetchRide();
    });

    SocketService.listenNegotiationOfferAcceptedByUser((data) {
      handleRideUpdate(data, "Offer selected successfully");
    });

    SocketService.listenNegotiationClosed((data) {
      handleRideUpdate(data, "Negotiation closed");
    });

    SocketService.listenNegotiationExpired((data) {
      handleRideUpdate(
        data,
        "Negotiation timed out. Retry negotiation or move to normal booking.",
      );
    });
  }

  Future<void> fetchRide() async {
    try {
      final response = await ApiService.getRide(widget.rideId);

      if (!mounted) {
        return;
      }

      final nextRide = response["ride"] is Map
          ? Map<String, dynamic>.from(response["ride"] as Map)
          : null;
      _applyRide(nextRide, nextMessage: response["message"]?.toString() ?? "");

      if (nextRide?["bookingMode"] == "negotiation") {
        await fetchOffers();
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
        isLoading = false;
      });
    }
  }

  Future<void> startRide() async {
    final otp = otpController.text.trim();
    if (otp.length != 4 || int.tryParse(otp) == null) {
      setState(() {
        message = "Please enter a valid 4-digit OTP code.";
      });
      return;
    }

    setState(() {
      actionLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.startRide(widget.rideId, otp);

      if (!mounted) {
        return;
      }

      setState(() {
        message = response["message"] ?? "Ride started successfully";
      });

      otpController.clear();
      await fetchRide();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          actionLoading = false;
        });
      }
    }
  }

  Future<void> completeRide() async {
    setState(() {
      actionLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.completeRide(widget.rideId);

      if (!mounted) {
        return;
      }

      setState(() {
        message = response["message"] ?? "Ride completed successfully";
      });

      await fetchRide();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          actionLoading = false;
        });
      }
    }
  }

  Future<void> cancelRide() async {
    setState(() {
      actionLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.cancelRide(widget.rideId);

      if (!mounted) {
        return;
      }

      setState(() {
        message = response["message"] ?? "Ride cancelled successfully";
      });

      await fetchRide();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          actionLoading = false;
        });
      }
    }
  }

  Future<void> payRide() async {
    setState(() {
      actionLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.payRide(widget.rideId);

      if (!mounted) {
        return;
      }

      setState(() {
        message = response["message"] ?? "Payment completed successfully";
      });

      await fetchRide();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          actionLoading = false;
        });
      }
    }
  }

  Future<void> fetchOffers() async {
    try {
      final response = await ApiService.getRideOffers(widget.rideId);

      if (!mounted) {
        return;
      }

      final rawRide = response["ride"] is Map
          ? Map<String, dynamic>.from(response["ride"] as Map)
          : null;
      final rawOffers = (response["offers"] as List<dynamic>? ??
              rawRide?["offers"] as List<dynamic>? ??
              const <dynamic>[])
          .whereType<Map>()
          .map((offer) => Map<String, dynamic>.from(offer))
          .toList();

      final nextOffers = rawOffers
        ..sort(
          (firstOffer, secondOffer) =>
              ((firstOffer["offeredFare"] as num?) ?? 0).compareTo(
                (secondOffer["offeredFare"] as num?) ?? 0,
              ),
        );

      final nextRide = rawRide ?? ride;

      setState(() {
        offers = nextOffers;
      });

      _applyRide(nextRide);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  Future<void> confirmOffer(String offerId) async {
    setState(() {
      actionLoading = true;
      message = "Selecting this offer...";
    });

    try {
      final response = await ApiService.confirmRideOffer(
        widget.rideId,
        offerId,
      );

      if (!mounted) {
        return;
      }

      final successMessage = response["message"]?.toString() ??
          "Offer selected successfully";

      setState(() {
        message = successMessage;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );

      await fetchRide();
    } catch (e) {
      if (!mounted) {
        return;
      }

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
          actionLoading = false;
        });
      }
    }
  }

  String? _rideUserId() {
    final userData = ride?["userId"];

    if (userData is Map && userData["_id"] != null) {
      return userData["_id"].toString();
    }

    if (userData != null) {
      return userData.toString();
    }

    return null;
  }

  Future<void> _rebookRide(String bookingMode) async {
    final userId = _rideUserId();
    final pickupAddress =
        ride?["pickupAddress"]?.toString() ?? ride?["pickup"]?.toString() ?? "";
    final dropAddress =
        ride?["dropAddress"]?.toString() ??
        ride?["destination"]?.toString() ??
        "";
    final pickupLat = _toDouble(ride?["pickupLat"]);
    final pickupLng = _toDouble(ride?["pickupLng"]);
    final dropLat = _toDouble(ride?["dropLat"] ?? ride?["destinationLat"]);
    final dropLng = _toDouble(ride?["dropLng"] ?? ride?["destinationLng"]);
    final paymentMethod = ride?["paymentMethod"]?.toString() ?? "Cash";
    final estimatedFare =
        _toDouble(
          ride?["estimatedFare"] ?? ride?["offeredFare"] ?? ride?["finalFare"],
        ) ??
        0;

    if (userId == null ||
        pickupAddress.isEmpty ||
        dropAddress.isEmpty ||
        pickupLat == null ||
        pickupLng == null ||
        dropLat == null ||
        dropLng == null) {
      setState(() {
        message =
            "Ride details are incomplete, so a fresh booking could not be created.";
      });
      return;
    }

    setState(() {
      actionLoading = true;
      message = "";
    });

    try {
      final response = await ApiService.requestRide(
        userId,
        pickupAddress,
        pickupLat,
        pickupLng,
        dropAddress,
        dropLat,
        dropLng,
        paymentMethod,
        ride?["pickupPlaceId"]?.toString(),
        ride?["dropPlaceId"]?.toString(),
        bookingMode,
        estimatedFare,
      );

      if (!mounted) {
        return;
      }

      final nextRideId = response["ride"]?["_id"]?.toString();
      if (nextRideId == null || nextRideId.isEmpty) {
        setState(() {
          message =
              response["message"]?.toString() ??
              "Booking created, but ride id was missing.";
        });
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => RideStatusScreen(rideId: nextRideId),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        message = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          actionLoading = false;
        });
      }
    }
  }

  String _formatCountdown(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return "${minutes.toString().padLeft(2, "0")}:${seconds.toString().padLeft(2, "0")}";
  }

  double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }

  Color _statusColor(String value) {
    switch (value.toLowerCase()) {
      case "completed":
      case "accepted":
      case "paid":
        return const Color(0xFF16A34A);
      case "ongoing":
      case "countered":
        return const Color(0xFF2563EB);
      case "cancelled":
      case "rejected":
      case "negotiation_expired":
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Widget _buildStatusChip(String label) {
    final color = _statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.replaceAll("_", " ").toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffersSection() {
    final currentFare =
        (ride?["offeredFare"] ?? ride?["estimatedFare"] ?? ride?["finalFare"])
            ?.toString() ??
        "N/A";

    return ReflectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Negotiation Offers",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text("Current fare: Rs. $currentFare"),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: Color(0xFFEA580C)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    negotiationSecondsRemaining > 0
                        ? "Waiting for offers: ${_formatCountdown(negotiationSecondsRemaining)} remaining"
                        : "Waiting for the server to finalize negotiation status...",
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (offers.isEmpty)
            const Text(
              "Waiting for driver offers...",
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            ...offers.map((offer) {
              final offerId = _normalizeOfferId(offer["_id"]) ?? "";
              final driverName = offer["driverName"]?.toString() ?? "Captain";
              final driverPhone = offer["driverPhone"]?.toString() ?? "N/A";
              final fare = offer["offeredFare"]?.toString() ?? "0";

              return Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.6)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driverName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text("Phone: $driverPhone"),
                          const SizedBox(height: 4),
                          Text("Offer: Rs. $fare"),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: actionLoading || offerId.isEmpty
                            ? null
                            : () => confirmOffer(offerId),
                        child: const Text(
                          "Accept Offer",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildExpiredNegotiationCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2).withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Negotiation Timed Out",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF9F1239)),
          ),
          const SizedBox(height: 8),
          const Text(
            "No offer was confirmed before the countdown ended. You can start a fresh negotiation or switch to direct booking.",
            style: TextStyle(color: Color(0xFFBE123C), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton(
                onPressed: actionLoading
                    ? null
                    : () => _rebookRide("negotiation"),
                child: const Text("Retry Negotiation"),
              ),
              OutlinedButton(
                onPressed: actionLoading ? null : () => _rebookRide("normal"),
                child: const Text("Move to Normal Ride"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final double pickupLat = _toDouble(ride?["pickupLat"]) ?? 0;
    final double pickupLng = _toDouble(ride?["pickupLng"]) ?? 0;
    final double destinationLat =
        _toDouble(ride?["dropLat"] ?? ride?["destinationLat"]) ?? pickupLat;
    final double destinationLng =
        _toDouble(ride?["dropLng"] ?? ride?["destinationLng"]) ?? pickupLng;

    final driverData = ride?["driverId"];
    final driverMap = driverData is Map ? driverData : null;
    final double? driverLat = driverMap != null ? _toDouble(driverMap["location"]?["lat"]) : null;
    final double? driverLng = driverMap != null ? _toDouble(driverMap["location"]?["lng"]) : null;

    final markers = <Marker>[
      Marker(
        point: LatLng(pickupLat, pickupLng),
        width: 40,
        height: 40,
        child: const Icon(Icons.location_on, color: Colors.green, size: 36),
      ),
      Marker(
        point: LatLng(destinationLat, destinationLng),
        width: 40,
        height: 40,
        child: const Icon(Icons.location_on, color: Colors.red, size: 36),
      ),
    ];

    if (driverLat != null && driverLng != null) {
      markers.add(
        Marker(
          point: LatLng(driverLat, driverLng),
          width: 40,
          height: 40,
          child: const Icon(
            Icons.directions_bike,
            color: Colors.blue,
            size: 32,
          ),
        ),
      );
    }

    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(pickupLat, pickupLng),
            initialZoom: 13,
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
              userAgentPackageName: "com.example.bike_taxi_app",
            ),
            MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ride?["status"]?.toString() ?? "";
    final pickupAddress =
        ride?["pickupAddress"]?.toString() ?? ride?["pickup"]?.toString() ?? "";
    final dropAddress =
        ride?["dropAddress"]?.toString() ??
        ride?["destination"]?.toString() ??
        "";
    final pickupCoords =
        "${ride?["pickupLat"] ?? "N/A"}, ${ride?["pickupLng"] ?? "N/A"}";
    final dropCoords =
        "${ride?["dropLat"] ?? ride?["destinationLat"] ?? "N/A"}, ${ride?["dropLng"] ?? ride?["destinationLng"] ?? "N/A"}";
    final dynamic negotiatedFare = ride?["offeredFare"] ?? ride?["finalFare"];
    final fare = (negotiatedFare != null && negotiatedFare != 0
            ? negotiatedFare
            : ride?["estimatedFare"])
        ?.toString() ??
        "N/A";
    final initialFare = ride?["initialFare"]?.toString() ?? "N/A";
    final offeredFare = ride?["offeredFare"]?.toString() ?? "N/A";
    final negotiationStatus = ride?["negotiationStatus"]?.toString() ?? "N/A";
    final paymentMethod = ride?["paymentMethod"]?.toString() ?? "N/A";
    final paymentStatus = ride?["paymentStatus"]?.toString() ?? "N/A";
    final bookingMode = ride?["bookingMode"]?.toString() ?? "normal";

    final driverData = ride?["driverId"];
    final driverMap = driverData is Map ? driverData : null;

    return Scaffold(
      appBar: AppBar(title: const Text("Ride Status")),
      body: PremiumBackdrop(
        child: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ReflectionCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Live Ride Overview",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: AppPalette.slate900,
                                  ),
                                ),
                                _buildStatusChip(status),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildMap(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (isNegotiationWaiting) ...[
                        _buildOffersSection(),
                        const SizedBox(height: 20),
                      ],
                      if (isNegotiationExpired) ...[
                        _buildExpiredNegotiationCard(),
                        const SizedBox(height: 20),
                      ],
                      ReflectionCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Ride Details",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.slate900,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (!widget.isDriver && ride?["otp"] != null && ride?["otp"].toString().isNotEmpty == true) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFFCD34D)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "SHARE OTP WITH DRIVER",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFB45309),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          "Give this OTP to start the ride",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF78350F),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      "${ride?["otp"]}",
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF92400E),
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildInfoRow("Booking Mode", bookingMode),
                            _buildInfoRow("Pickup", pickupAddress),
                            _buildInfoRow("Drop", dropAddress),
                            _buildInfoRow("Fare", "Rs. $fare"),
                            _buildInfoRow("Offered Fare", offeredFare),
                            _buildInfoRow("Negotiation", negotiationStatus),
                            _buildInfoRow("Payment Method", paymentMethod),
                            _buildInfoRow(
                              "Driver",
                              "${driverMap?["name"] ?? "N/A"}",
                            ),
                            _buildInfoRow(
                              "Phone",
                              "${driverMap?["phone"] ?? "N/A"}",
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ReflectionCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Actions",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.slate900,
                              ),
                            ),
                            const SizedBox(height: 16),
                             if (status == "accepted") ...[
                                 if (widget.isDriver) ...[
                                   TextField(
                                     controller: otpController,
                                     keyboardType: TextInputType.number,
                                     maxLength: 4,
                                     decoration: const InputDecoration(
                                       labelText: "Enter Rider's 4-Digit OTP",
                                       hintText: "4-Digit OTP code",
                                       counterText: "",
                                       prefixIcon: Icon(Icons.lock_open_rounded),
                                     ),
                                   ),
                                   const SizedBox(height: 12),
                                   ElevatedButton(
                                     onPressed: actionLoading ? null : startRide,
                                     child: const Text("Verify & Start Ride"),
                                   ),
                               ] else ...[
                                 Container(
                                   padding: const EdgeInsets.all(12),
                                   decoration: BoxDecoration(
                                     color: const Color(0xFFEFF6FF),
                                     borderRadius: BorderRadius.circular(12),
                                     border: Border.all(color: const Color(0xFF93C5FD)),
                                   ),
                                   child: Row(
                                     children: [
                                       const Icon(Icons.info_outline_rounded, color: AppPalette.primary),
                                       const SizedBox(width: 8),
                                       Expanded(
                                         child: Text(
                                           "Waiting for driver to reach you and start the ride.",
                                           style: TextStyle(
                                             fontWeight: FontWeight.bold,
                                             color: AppPalette.primary,
                                           ),
                                         ),
                                       ),
                                     ],
                                   ),
                                 ),
                               ],
                               const SizedBox(height: 10),
                             ],
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
                            if (status == "completed" &&
                                paymentStatus == "Pending") ...[
                                const SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: actionLoading ? null : payRide,
                                  child: const Text("Pay Now"),
                                ),
                            ],
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: fetchRide,
                              child: const Text("Refresh Status"),
                            ),
                          ],
                        ),
                      ),
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        ReflectionCard(
                          padding: const EdgeInsets.all(16),
                          child: Text(message),
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

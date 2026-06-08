import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../theme/premium_ui.dart';
import 'driver_screen.dart';
import 'home_screen.dart';

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
  String? overridePaymentMethod;

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
    SocketService.stopListeningDriverLocationUpdated();
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

    if (nextRide != null) {
      final status = nextRide["status"]?.toString();
      final paymentStatus = nextRide["paymentStatus"]?.toString();

      if ((status == "completed" && paymentStatus == "Paid") ||
          status == "cancelled") {
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          if (widget.isDriver) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => DriverScreen(
                  driverId: nextRide["driverId"]?.toString() ?? "",
                ),
              ),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomeScreen(
                  userId: nextRide["userId"]?.toString() ?? "",
                ),
              ),
            );
          }
        });
      }
    }
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

    SocketService.listenDriverLocationUpdated((data) {
      if (data == null) return;
      final driverId = data["driverId"]?.toString() ?? "";
      final lat = data["lat"];
      final lng = data["lng"];
      
      String? currentDriverId;
      if (ride != null && ride!["driverId"] != null) {
        final driverData = ride!["driverId"];
        if (driverData is Map) {
          currentDriverId = driverData["_id"]?.toString();
        } else {
          currentDriverId = driverData.toString();
        }
      }

      if (mounted && driverId.isNotEmpty && currentDriverId == driverId) {
        setState(() {
          if (ride != null) {
            final nextRide = Map<String, dynamic>.from(ride!);
            if (nextRide["driverId"] is Map) {
              final driverMap = Map<String, dynamic>.from(nextRide["driverId"]);
              driverMap["location"] = {"lat": lat, "lng": lng};
              nextRide["driverId"] = driverMap;
            } else {
              nextRide["driverId"] = {
                "_id": driverId,
                "location": {"lat": lat, "lng": lng}
              };
            }
            ride = nextRide;
          }
        });
      }
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

  void _showUPIQRCodeDialog(BuildContext context, String fare) {
    final String upiUrl = "upi://pay?pa=captain@upi&pn=Captain&am=$fare&cu=INR&tn=RidePayment";
    final String qrImageUrl = "https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(upiUrl)}";

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ReflectionCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "UPI QR Code",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Fare: Rs. $fare",
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.primary,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: Image.network(
                      qrImageUrl,
                      width: 200,
                      height: 200,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox(
                          width: 200,
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey.shade100,
                          child: const Center(
                            child: Icon(Icons.error_outline, color: Colors.red, size: 48),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Ask the rider to scan this QR code to pay using Google Pay, PhonePe, Paytm, or BHIM.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _processRiderUPIPayment(BuildContext context, String appName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ReflectionCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(strokeWidth: 5),
                ),
                const SizedBox(height: 24),
                Text(
                  "Connecting to $appName...",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Please authorize the payment request on your phone.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    Navigator.pop(context); // Close the processing dialog

    await payRide();
  }

  void _showRiderUPISelector(BuildContext context, String fare) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Select UPI App",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Pay Rs. $fare using your preferred UPI app",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(Icons.phone_android_rounded, color: Colors.blue),
                    title: const Text("Google Pay", style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _processRiderUPIPayment(context, "Google Pay");
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_rounded, color: Colors.purple),
                    title: const Text("PhonePe", style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _processRiderUPIPayment(context, "PhonePe");
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.payment_rounded, color: Colors.cyan),
                    title: const Text("Paytm", style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _processRiderUPIPayment(context, "Paytm");
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.security_rounded, color: Colors.green),
                    title: const Text("BHIM UPI", style: TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _processRiderUPIPayment(context, "BHIM UPI");
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _processRiderCardPayment(BuildContext context) async {
    final cardNoController = TextEditingController();
    final expiryController = TextEditingController();
    final cvvController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ReflectionCard(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Enter Card Details",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: cardNoController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Card Number",
                        hintText: "1234 5678 1234 5678",
                        prefixIcon: Icon(Icons.credit_card),
                      ),
                      validator: (v) => (v == null || v.length < 16) ? "Invalid Card" : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: expiryController,
                            keyboardType: TextInputType.datetime,
                            decoration: const InputDecoration(
                              labelText: "Expiry (MM/YY)",
                              hintText: "12/28",
                            ),
                            validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: cvvController,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: "CVV",
                              hintText: "123",
                            ),
                            validator: (v) => (v == null || v.length < 3) ? "Invalid" : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        if (formKey.currentState?.validate() ?? false) {
                          Navigator.pop(context); // Close details dialog
                          
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => Dialog(
                              backgroundColor: Colors.transparent,
                              child: ReflectionCard(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text("Processing card payment..."),
                                  ],
                                ),
                              ),
                            ),
                          );
                          
                          await Future.delayed(const Duration(seconds: 2));
                          if (!mounted) return;
                          Navigator.pop(context); // Close loading
                          await payRide();
                        }
                      },
                      child: const Text("Pay Now"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
                color: AppPalette.slate900,
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
              color: AppPalette.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.primary.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: AppPalette.primary),
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
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
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
        color: const Color(0xFF93000A).withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFB4AB).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Negotiation Timed Out",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFFFB4AB)),
          ),
          const SizedBox(height: 8),
          const Text(
            "No offer was confirmed before the countdown ended. You can start a fresh negotiation or switch to direct booking.",
            style: TextStyle(color: Color(0xFFFFDAD6), fontWeight: FontWeight.w600),
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
    final dbPaymentMethod = ride?["paymentMethod"]?.toString() ?? "N/A";
    final paymentMethod = overridePaymentMethod ?? dbPaymentMethod;
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
                      ReflectionCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Route Details",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.slate900,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.18)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.my_location_rounded, color: Color(0xFF16A34A), size: 24),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Pickup Point",
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF16A34A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          pickupAddress,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppPalette.slate900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.18)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.flag_rounded, color: Color(0xFFDC2626), size: 24),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Drop Point",
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFDC2626),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          dropAddress,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: AppPalette.slate900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                  color: AppPalette.accent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppPalette.accent.withOpacity(0.3)),
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
                                            color: AppPalette.primary,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          "Give this OTP to start the ride",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppPalette.slate700,
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
                                        color: AppPalette.primary,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildInfoRow("Booking Mode", bookingMode),
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
                                 Row(
                                   children: [
                                     Expanded(
                                       flex: 3,
                                       child: ElevatedButton(
                                         style: ElevatedButton.styleFrom(
                                           padding: const EdgeInsets.symmetric(vertical: 12),
                                         ),
                                         onPressed: actionLoading ? null : startRide,
                                         child: const Text("Verify & Start"),
                                       ),
                                     ),
                                     const SizedBox(width: 12),
                                     Expanded(
                                       flex: 2,
                                       child: OutlinedButton(
                                         style: OutlinedButton.styleFrom(
                                           padding: const EdgeInsets.symmetric(vertical: 12),
                                           foregroundColor: Colors.redAccent,
                                           side: const BorderSide(color: Colors.redAccent),
                                         ),
                                         onPressed: actionLoading ? null : cancelRide,
                                         child: const Text("Cancel"),
                                       ),
                                     ),
                                   ],
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
                                 const SizedBox(height: 12),
                                 SizedBox(
                                   width: double.infinity,
                                   child: OutlinedButton(
                                     style: OutlinedButton.styleFrom(
                                       padding: const EdgeInsets.symmetric(vertical: 12),
                                       foregroundColor: Colors.redAccent,
                                       side: const BorderSide(color: Colors.redAccent),
                                     ),
                                     onPressed: actionLoading ? null : cancelRide,
                                     child: const Text("Cancel Ride"),
                                   ),
                                 ),
                               ],
                               const SizedBox(height: 10),
                             ],
                             if (status == "ongoing") ...[
                               Row(
                                 children: [
                                   if (widget.isDriver) ...[
                                     Expanded(
                                       flex: 3,
                                       child: ElevatedButton(
                                         style: ElevatedButton.styleFrom(
                                           padding: const EdgeInsets.symmetric(vertical: 12),
                                           backgroundColor: AppPalette.secondary,
                                         ),
                                         onPressed: actionLoading ? null : completeRide,
                                         child: const Text("Complete Ride"),
                                       ),
                                     ),
                                     const SizedBox(width: 12),
                                     Expanded(
                                       flex: 2,
                                       child: OutlinedButton(
                                         style: OutlinedButton.styleFrom(
                                           padding: const EdgeInsets.symmetric(vertical: 12),
                                           foregroundColor: Colors.redAccent,
                                           side: const BorderSide(color: Colors.redAccent),
                                         ),
                                         onPressed: actionLoading ? null : cancelRide,
                                         child: const Text("Cancel"),
                                       ),
                                     ),
                                   ] else ...[
                                     Expanded(
                                       child: OutlinedButton(
                                         style: OutlinedButton.styleFrom(
                                           padding: const EdgeInsets.symmetric(vertical: 12),
                                           foregroundColor: Colors.redAccent,
                                           side: const BorderSide(color: Colors.redAccent),
                                         ),
                                         onPressed: actionLoading ? null : cancelRide,
                                         child: const Text("Cancel Ride"),
                                       ),
                                     ),
                                   ],
                                 ],
                               ),
                               const SizedBox(height: 10),
                             ],
                            if (status == "completed" &&
                                paymentStatus == "Pending") ...[
                              const SizedBox(height: 10),
                              if (widget.isDriver) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppPalette.secondary,
                                        ),
                                        onPressed: () => _showUPIQRCodeDialog(context, fare),
                                        child: const Text("Generate QR Code"),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: actionLoading ? null : payRide,
                                        child: const Text("Cash Paid"),
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                if (paymentMethod == "Cash") ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFF93C5FD)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.payments_rounded, color: AppPalette.primary, size: 28),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Please pay Captain Rs. $fare in Cash",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: AppPalette.slate900,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              const Text(
                                                "Waiting for Captain to confirm cash receipt...",
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: AppPalette.slate600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (paymentMethod == "UPI") ...[
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppPalette.primary,
                                    ),
                                    onPressed: () => _showRiderUPISelector(context, fare),
                                    child: const Text("Pay Now (UPI)"),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 54),
                                      side: const BorderSide(color: AppPalette.primary),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        overridePaymentMethod = "Cash";
                                      });
                                    },
                                    child: const Text("Pay via Cash"),
                                  ),
                                ] else if (paymentMethod == "Card") ...[
                                  ElevatedButton(
                                    onPressed: () => _processRiderCardPayment(context),
                                    child: const Text("Pay Now (Card)"),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 54),
                                      side: const BorderSide(color: AppPalette.primary),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        overridePaymentMethod = "Cash";
                                      });
                                    },
                                    child: const Text("Pay via Cash"),
                                  ),
                                ] else ...[
                                  ElevatedButton(
                                    onPressed: actionLoading ? null : payRide,
                                    child: const Text("Pay Now"),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(double.infinity, 54),
                                      side: const BorderSide(color: AppPalette.primary),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        overridePaymentMethod = "Cash";
                                      });
                                    },
                                    child: const Text("Pay via Cash"),
                                  ),
                                ],
                              ],
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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/session_service.dart';
import '../services/location_service.dart';
import '../services/routing_service.dart';
import '../config/app_config.dart';
import '../theme/premium_ui.dart';
import '../utils/location_display.dart';

enum RideMode { negotiation, normal }

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

  bool normalModeTimeout = false;
  Timer? _normalTimeoutTimer;
  List<LatLng> _roadRoutePoints = [];
  LatLng? _captainLocation;
  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  LatLng? _riderLiveLocation;
  double _riderHeading = 0.0;
  List<LatLng> _liveRoutePoints = [];
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  double? liveRiderLat;
  double? liveRiderLng;
  Timer? _liveLocationTimer;
  Timer? _demoCaptainRouteTimer;
  StreamSubscription<Position>? _positionStreamSubscription;
  String? _lastRouteKey;
  String? _lastRouteStatus;

  RideMode get rideMode => isNegotiationRide ? RideMode.negotiation : RideMode.normal;

  void _startRiderPositionStream() {
    if (widget.isDriver) return;
    try {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      );

      Geolocator.getCurrentPosition(locationSettings: locationSettings)
          .then((Position position) {
        if (!mounted || _riderLiveLocation != null) return;
        final initialPoint = LatLng(position.latitude, position.longitude);
        final double initialHeading =
            (!position.heading.isNaN && position.heading >= 0)
                ? position.heading
                : 0.0;
        setState(() {
          _riderLiveLocation = initialPoint;
          liveRiderLat = position.latitude;
          liveRiderLng = position.longitude;
          _riderHeading = initialHeading;
        });
        SocketService.emitUpdateRiderLocation(
          widget.rideId,
          position.latitude,
          position.longitude,
        );
      }).catchError((err) {
        debugPrint("[Geolocator.getCurrentPosition] error: $err");
      });

      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          if (!mounted) return;
          final nextPoint = LatLng(position.latitude, position.longitude);
          final double nextHeading =
              (!position.heading.isNaN && position.heading >= 0)
                  ? position.heading
                  : _riderHeading;
          setState(() {
            _riderLiveLocation = nextPoint;
            liveRiderLat = position.latitude;
            liveRiderLng = position.longitude;
            _riderHeading = nextHeading;
          });
          SocketService.emitUpdateRiderLocation(
            widget.rideId,
            position.latitude,
            position.longitude,
          );
        },
        onError: (err) {
          debugPrint("[Geolocator.getPositionStream] error: $err");
        },
      );
    } catch (e) {
      debugPrint("[Geolocator.getPositionStream] setup exception: $e");
    }
  }

  void _startLiveLocationTracking() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      try {
        if (!widget.isDriver && _riderLiveLocation != null) {
          SocketService.emitUpdateRiderLocation(
            widget.rideId,
            _riderLiveLocation!.latitude,
            _riderLiveLocation!.longitude,
          );
          return;
        }
        final pos = await LocationService.getBestCurrentLocation(
          timeout: const Duration(seconds: 3),
          allowFallback: widget.isDriver,
        );
        if (pos != null && pos['lat'] != null && pos['lng'] != null && mounted) {
          final lat = pos['lat']!;
          final lng = pos['lng']!;
          if (widget.isDriver) {
            final session = SessionService.loadSession();
            final driverId = session?["userId"] ?? "";
            SocketService.emitUpdateDriverLocation(widget.rideId, driverId, lat, lng);
          } else {
            if (_riderLiveLocation == null) {
              setState(() {
                _riderLiveLocation = LatLng(lat, lng);
                liveRiderLat = lat;
                liveRiderLng = lng;
              });
            }
            SocketService.emitUpdateRiderLocation(widget.rideId, lat, lng);
          }
        }
      } catch (_) {}
    });
  }

  void _startNormalTimeoutTimer() {
    _cancelNormalTimeoutTimer();
    if (isNormalWaiting) {
      _normalTimeoutTimer = Timer(const Duration(seconds: 75), () {
        if (mounted && isNormalWaiting) {
          setState(() {
            normalModeTimeout = true;
          });
        }
      });
    }
  }

  void _cancelNormalTimeoutTimer() {
    _normalTimeoutTimer?.cancel();
    _normalTimeoutTimer = null;
  }

  String _formatFareToInt(dynamic rawFare) {
    if (rawFare == null) return "N/A";
    final parsed = double.tryParse(rawFare.toString());
    if (parsed == null) {
      if (rawFare.toString() == "N/A") return "N/A";
      return rawFare.toString();
    }
    return parsed.round().toStringAsFixed(2);
  }

  bool get isNegotiationRide =>
      ride?["bookingMode"]?.toString() == "negotiation";

  bool get isNormalRide =>
      ride?["bookingMode"]?.toString() == "normal";

  bool get isNegotiationWaiting =>
      isNegotiationRide && ride?["status"]?.toString() == "negotiating";

  bool get isNormalWaiting =>
      isNormalRide && ride?["status"]?.toString() == "requested";

  bool get isWaiting => isNegotiationWaiting || isNormalWaiting;

  bool get isNegotiationExpired =>
      isNegotiationRide && ride?["status"]?.toString() == "negotiation_expired";

  @override
  void initState() {
    super.initState();
    SocketService.emitJoinRide(widget.rideId);
    _startLiveLocationTracking();
    _startRiderPositionStream();
    fetchRide();
    listenToRideEvents();
  }

  @override
  void dispose() {
    _demoCaptainRouteTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _liveLocationTimer?.cancel();
    _cancelNormalTimeoutTimer();
    countdownTimer?.cancel();
    SocketService.removeAllRideListeners();
    SocketService.stopListeningDriverLocationUpdated();
    SocketService.stopListeningRideDriverLocationUpdated();
    SocketService.stopListeningRiderLocationUpdated();
    otpController.dispose();
    super.dispose();
  }

  void _syncCountdownFromRide() {
    countdownTimer?.cancel();
    negotiationSecondsRemaining = 0;

    if (!isWaiting) {
      _cancelNormalTimeoutTimer();
      return;
    }

    if (isNormalWaiting) {
      if (_normalTimeoutTimer == null && !normalModeTimeout) {
        _startNormalTimeoutTimer();
      }
    } else {
      _cancelNormalTimeoutTimer();
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
          if (mounted && (ride?["status"]?.toString() == "negotiating" || ride?["status"]?.toString() == "requested")) {
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

  void _frameCamera(LatLng p1, LatLng p2) {
    if (!_isMapReady) return;
    try {
      final bounds = LatLngBounds.fromPoints([p1, p2]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(40.0),
        ),
      );
    } catch (e) {
      debugPrint("[RideMap] fitCamera error: $e");
    }
  }

  Future<void> _recalculateRouteForCurrentStatus() async {
    final status = ride?["status"]?.toString().toLowerCase() ?? "";
    final bool isAcceptedOrArriving =
        status == "accepted" || status == "arriving";
    final bool isInProgressOrStarted =
        status == "in_progress" || status == "started" || status == "ongoing";

    LatLng? start;
    LatLng? end;
    bool shouldFrame = false;

    if (isAcceptedOrArriving) {
      start = _captainLocation;
      end = _pickupLocation;
      shouldFrame = true;
      if (start == null || end == null) {
        if (_lastRouteStatus != status) {
          _lastRouteStatus = status;
          _lastRouteKey = null;
          if (mounted &&
              (_liveRoutePoints.isNotEmpty || _roadRoutePoints.isNotEmpty)) {
            setState(() {
              _liveRoutePoints = [];
              _roadRoutePoints = [];
            });
          }
        }
        return;
      }
    } else if (isInProgressOrStarted) {
      start = _captainLocation ?? _pickupLocation;
      end = _dropLocation;
      shouldFrame = true;
    } else {
      start = _pickupLocation;
      end = _dropLocation;
    }

    if (start == null || end == null) return;
    final LatLng routeStart = start;
    final LatLng routeEnd = end;

    final String nextKey =
        "$status|${routeStart.latitude.toStringAsFixed(5)},${routeStart.longitude.toStringAsFixed(5)}|${routeEnd.latitude.toStringAsFixed(5)},${routeEnd.longitude.toStringAsFixed(5)}";
    if (_lastRouteKey == nextKey && _liveRoutePoints.isNotEmpty) {
      return;
    }
    _lastRouteKey = nextKey;
    _lastRouteStatus = status;

    try {
      final result = await RoutingService.getRoute(
        routeStart.latitude,
        routeStart.longitude,
        routeEnd.latitude,
        routeEnd.longitude,
      );
      if (!mounted) return;
      final currentStatus = ride?["status"]?.toString().toLowerCase() ?? "";
      if (currentStatus != status) return;

      final List<LatLng> points = result?.points ?? [routeStart, routeEnd];
      setState(() {
        _liveRoutePoints = points;
        _roadRoutePoints = points;
      });
      if (shouldFrame) {
        _frameCamera(routeStart, routeEnd);
      }
      if (isAcceptedOrArriving) {
        _startDemoCaptainRouteAnimation();
      }
    } catch (_) {
      if (!mounted) return;
      final currentStatus = ride?["status"]?.toString().toLowerCase() ?? "";
      if (currentStatus != status) return;
      setState(() {
        _liveRoutePoints = [routeStart, routeEnd];
        _roadRoutePoints = [routeStart, routeEnd];
      });
      if (shouldFrame) {
        _frameCamera(routeStart, routeEnd);
      }
      if (isAcceptedOrArriving) {
        _startDemoCaptainRouteAnimation();
      }
    }
  }

  void _startDemoCaptainRouteAnimation() {
    final status = ride?["status"]?.toString().toLowerCase() ?? "";
    final bool isDemo = ride?["isDemoMode"] == true;
    if (!isDemo || (status != "accepted" && status != "arriving")) {
      _demoCaptainRouteTimer?.cancel();
      _demoCaptainRouteTimer = null;
      return;
    }
    if (_demoCaptainRouteTimer != null && _demoCaptainRouteTimer!.isActive) {
      return;
    }
    _demoCaptainRouteTimer =
        Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final curStatus = ride?["status"]?.toString().toLowerCase() ?? "";
      if (curStatus != "accepted" && curStatus != "arriving") {
        timer.cancel();
        _demoCaptainRouteTimer = null;
        return;
      }
      if (_liveRoutePoints.length <= 2) {
        if (_pickupLocation != null) {
          setState(() {
            _captainLocation = _pickupLocation;
          });
        }
        timer.cancel();
        _demoCaptainRouteTimer = null;
        return;
      }
      final int step = (_liveRoutePoints.length / 10).ceil().clamp(1, 3);
      final int nextIndex = step.clamp(1, _liveRoutePoints.length - 1);
      final remaining = _liveRoutePoints.sublist(nextIndex);
      setState(() {
        _captainLocation = remaining.first;
        _liveRoutePoints = remaining;
        _roadRoutePoints = remaining;
      });
    });
  }

  void _applyRide(Map<String, dynamic>? nextRide, {String? nextMessage}) {
    if (!mounted) {
      return;
    }

    List<Map<String, dynamic>>? syncedOffers;
    if (nextRide != null && nextRide["offers"] is List) {
      syncedOffers = (nextRide["offers"] as List<dynamic>)
          .whereType<Map>()
          .map((o) => Map<String, dynamic>.from(o))
          .where((o) => o["status"]?.toString() != "rejected")
          .toList()
        ..sort((a, b) => ((a["offeredFare"] as num?) ?? 0)
            .compareTo((b["offeredFare"] as num?) ?? 0));
    }

    setState(() {
      ride = nextRide;
      if (syncedOffers != null) {
        offers = syncedOffers;
      }
      if (nextMessage != null) {
        message = nextMessage;
      }
      isLoading = false;
    });

    _syncCountdownFromRide();

    if (nextRide != null) {
      final double pickupLat = _toDouble(nextRide["pickupLat"]) ?? 0;
      final double pickupLng = _toDouble(nextRide["pickupLng"]) ?? 0;
      final double destinationLat =
          _toDouble(nextRide["dropLat"] ?? nextRide["destinationLat"]) ?? pickupLat;
      final double destinationLng =
          _toDouble(nextRide["dropLng"] ?? nextRide["destinationLng"]) ?? pickupLng;

      if (pickupLat != 0 && pickupLng != 0) {
        _pickupLocation = LatLng(pickupLat, pickupLng);
      }
      if (destinationLat != 0 && destinationLng != 0) {
        _dropLocation = LatLng(destinationLat, destinationLng);
      }

      double? dLat;
      double? dLng;
      final driverData = nextRide["driverId"] ?? nextRide["driver"];
      if (driverData is Map) {
        final loc = driverData["location"];
        if (loc is Map) {
          dLat = _toDouble(loc["lat"]);
          dLng = _toDouble(loc["lng"]);
        }
      }
      dLat ??= _toDouble(nextRide["driverLat"] ?? nextRide["driverLocation"]?["lat"]);
      dLng ??= _toDouble(nextRide["driverLng"] ?? nextRide["driverLocation"]?["lng"]);

      if (dLat != null && dLng != null && dLat != 0 && dLng != 0) {
        _captainLocation = LatLng(dLat, dLng);
      }

      final lowerStatus = nextRide["status"]?.toString().toLowerCase() ?? "";
      if (lowerStatus != "accepted" && lowerStatus != "arriving") {
        _demoCaptainRouteTimer?.cancel();
        _demoCaptainRouteTimer = null;
      }

      _recalculateRouteForCurrentStatus();

      final status = nextRide["status"]?.toString();
      final paymentStatus = nextRide["paymentStatus"]?.toString();

      if ((status == "completed" && paymentStatus == "Paid") ||
          status == "cancelled") {
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          if (widget.isDriver) {
            context.go('/driver');
          } else {
            context.go('/home');
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

    SocketService.listenRideUpdated((data) {
      handleRideUpdate(data, "Ride updated");
    });

    SocketService.listenRideCounterOffer((data) {
      if (!mounted || data == null) return;
      final dataMap = data is Map ? Map<String, dynamic>.from(data) : null;
      if (dataMap == null) return;
      final rideId = _normalizeRideId(dataMap["rideId"] ?? dataMap["ride"]?["_id"]);
      if (rideId != null && rideId != widget.rideId) return;

      if (dataMap["ride"] is Map) {
        _applyRide(
          Map<String, dynamic>.from(dataMap["ride"] as Map),
          nextMessage: "Captain counter offer received",
        );
      } else {
        setState(() {
          if (ride != null) {
            final nextRide = Map<String, dynamic>.from(ride!);
            nextRide["negotiationStatus"] =
                dataMap["negotiationStatus"] ?? "countered";
            if (dataMap["counterOffer"] != null) {
              nextRide["counterOffer"] = dataMap["counterOffer"];
            }
            if (dataMap["captain"] is Map) {
              nextRide["driverId"] = dataMap["captain"];
            }
            ride = nextRide;
          }
          if (dataMap["offer"] is Map) {
            final incomingOffer = Map<String, dynamic>.from(dataMap["offer"] as Map);
            final incomingId = _normalizeOfferId(incomingOffer["_id"]);
            final idx = offers.indexWhere((o) => _normalizeOfferId(o["_id"]) == incomingId);
            if (idx != -1) {
              offers[idx] = incomingOffer;
            } else {
              offers = [...offers, incomingOffer];
            }
          }
        });
      }
    });

    void onDriverLocationReceived(dynamic data) {
      if (data == null || !mounted) return;
      final driverId = data["driverId"]?.toString() ?? "";
      final lat = _toDouble(data["lat"]);
      final lng = _toDouble(data["lng"]);

      String? currentDriverId;
      if (ride != null && ride!["driverId"] != null) {
        final driverData = ride!["driverId"];
        if (driverData is Map) {
          currentDriverId = driverData["_id"]?.toString();
        } else {
          currentDriverId = driverData.toString();
        }
      }

      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        if (currentDriverId == null || currentDriverId == driverId) {
          setState(() {
            _captainLocation = LatLng(lat, lng);
            if (ride != null) {
              final nextRide = Map<String, dynamic>.from(ride!);
              if (nextRide["driverId"] is Map) {
                final driverMap = Map<String, dynamic>.from(nextRide["driverId"]);
                driverMap["location"] = {"lat": lat, "lng": lng};
                nextRide["driverId"] = driverMap;
              } else {
                nextRide["driverId"] = {
                  "_id": driverId,
                  "location": {"lat": lat, "lng": lng},
                };
              }
              ride = nextRide;
            }
          });
          _recalculateRouteForCurrentStatus();
        }
      }
    }

    SocketService.listenRideDriverLocationUpdated(onDriverLocationReceived);
    SocketService.listenDriverLocationUpdated(onDriverLocationReceived);

    SocketService.listenRiderLocationUpdated((data) {
      if (data == null) return;
      final rideId = _normalizeRideId(data["rideId"]);
      if (rideId != null && rideId != widget.rideId) return;
      final lat = _toDouble(data["lat"]);
      final lng = _toDouble(data["lng"]);
      final heading = _toDouble(data["heading"]);
      if (mounted && lat != null && lng != null) {
        if (!widget.isDriver && _riderLiveLocation != null) {
          return;
        }
        setState(() {
          _riderLiveLocation = LatLng(lat, lng);
          liveRiderLat = lat;
          liveRiderLng = lng;
          if (heading != null && !heading.isNaN && heading >= 0) {
            _riderHeading = heading;
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
    final String upiUrl =
        "upi://pay?pa=captain@upi&pn=Captain&am=$fare&cu=INR&tn=RidePayment";
    final String qrImageUrl =
        "https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(upiUrl)}";

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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey.shade100,
                          child: const Center(
                            child: Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 48,
                            ),
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
                  style: TextStyle(fontSize: 13, color: Colors.grey),
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

  Future<void> _processRiderUPIPayment(
    BuildContext context,
    String appName,
  ) async {
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
                  style: TextStyle(fontSize: 13, color: Colors.grey),
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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Pay Rs. $fare using your preferred UPI app",
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: const Icon(
                      Icons.phone_android_rounded,
                      color: Colors.blue,
                    ),
                    title: const Text(
                      "Google Pay",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _processRiderUPIPayment(context, "Google Pay");
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.purple,
                    ),
                    title: const Text(
                      "PhonePe",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _processRiderUPIPayment(context, "PhonePe");
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.payment_rounded,
                      color: Colors.cyan,
                    ),
                    title: const Text(
                      "Paytm",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _processRiderUPIPayment(context, "Paytm");
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.security_rounded,
                      color: Colors.green,
                    ),
                    title: const Text(
                      "BHIM UPI",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                      validator: (v) =>
                          (v == null || v.length < 16) ? "Invalid Card" : null,
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
                            validator: (v) =>
                                (v == null || v.isEmpty) ? "Required" : null,
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
                            validator: (v) =>
                                (v == null || v.length < 3) ? "Invalid" : null,
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
      final rawOffers =
          (response["offers"] as List<dynamic>? ??
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
      message = "Accepting counter offer...";
    });

    try {
      final response = offerId.isNotEmpty
          ? await ApiService.confirmRideOffer(widget.rideId, offerId)
          : await ApiService.acceptFare(widget.rideId);

      if (!mounted) {
        return;
      }

      final successMessage =
          response["message"]?.toString() ?? "Offer accepted successfully";

      if (response["ride"] is Map) {
        _applyRide(
          Map<String, dynamic>.from(response["ride"] as Map),
          nextMessage: successMessage,
        );
      } else {
        setState(() {
          message = successMessage;
        });
        await fetchRide();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) {
        return;
      }

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
          actionLoading = false;
        });
      }
    }
  }

  Future<void> _acceptCounterOffer(Map<String, dynamic> offer) async {
    final offerId = _normalizeOfferId(offer["_id"]) ?? "";
    await confirmOffer(offerId);
  }

  Future<void> _declineOffer(String offerId) async {
    final remainingCount = offers
        .where((o) =>
            _normalizeOfferId(o["_id"]) != offerId &&
            o["status"]?.toString() != "rejected")
        .length;

    if (remainingCount == 0) {
      setState(() {
        actionLoading = true;
      });
      try {
        await ApiService.rejectFare(widget.rideId);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      actionLoading = false;
      offers.removeWhere((o) => _normalizeOfferId(o["_id"]) == offerId);
      if (ride != null && remainingCount == 0) {
        final nextRide = Map<String, dynamic>.from(ride!);
        nextRide["negotiationStatus"] = "rejected";
        nextRide["counterOffer"] = 0;
        ride = nextRide;
      }
    });
    _showSnack("Offer declined");
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
    final pickupAddress = readableLocationLabel(
      ride?["pickupAddress"]?.toString() ?? ride?["pickup"]?.toString(),
      fallback: "Pickup address",
    );
    final dropAddress = readableLocationLabel(
      ride?["dropAddress"]?.toString() ?? ride?["destination"]?.toString(),
      fallback: "Drop address",
    );
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

      context.go('/ride-status/$nextRideId');
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

  // ── driver assigned card (rider view, status = accepted) ─────────────────
  Widget _buildDriverAssignedCard({
    required Map<String, dynamic> driverMap,
    required String otp,
    required String fare,
    required String pickupAddress,
    required String dropAddress,
    required String status,
  }) {
    final name = driverMap["name"]?.toString() ?? "Captain";
    final phone = driverMap["phone"]?.toString() ?? "";
    final bikeModel = driverMap["bikeModel"]?.toString() ??
        driverMap["vehicleModel"]?.toString() ??
        "Bike";
    final registration = driverMap["registrationNumber"]?.toString() ??
        driverMap["vehicleNumber"]?.toString() ??
        "N/A";
    final rating = driverMap["rating"]?.toString() ?? "4.8";
    final initials = name
        .trim()
        .split(" ")
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF141616),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF4A261).withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF4A261).withOpacity(0.07),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
            decoration: BoxDecoration(
              color: const Color(0xFFF4A261).withOpacity(0.07),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFF4A261).withOpacity(0.15),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  status == "ongoing" ? Icons.two_wheeler : Icons.check_circle_rounded,
                  color: status == "ongoing" ? const Color(0xFF60A5FA) : const Color(0xFF4ADE80),
                  size: 17,
                ),
                const SizedBox(width: 8),
                Text(
                  status == "ongoing" ? "Trip Ongoing · En route" : "Driver Assigned · On the way",
                  style: TextStyle(
                    color: status == "ongoing" ? const Color(0xFF60A5FA) : const Color(0xFF4ADE80),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4A261).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "₹ $fare",
                    style: const TextStyle(
                      color: Color(0xFFF4A261),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Driver profile row
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4A261).withOpacity(0.14),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFF4A261).withOpacity(0.38),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initials.isEmpty ? "C" : initials,
                          style: const TextStyle(
                            color: Color(0xFFF4A261),
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFF59E0B),
                                size: 15,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                rating,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.70),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.two_wheeler_rounded,
                                color: Colors.white.withOpacity(0.45),
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  "$bikeModel  ·  $registration",
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.50),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // OTP digits
                if (otp.isNotEmpty && status == "accepted") ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1A0D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF16A34A).withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "RIDE OTP",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF4ADE80).withOpacity(0.8),
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Share with driver to start",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.35),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: otp.split("").map((digit) {
                            return Container(
                              width: 34,
                              height: 42,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withOpacity(0.14),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF16A34A).withOpacity(0.38),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  digit,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF4ADE80),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Action buttons: Call, Chat, Share Ride
                Row(
                  children: [
                    Expanded(
                      child: _driverActionButton(
                        icon: Icons.call_rounded,
                        label: "Call",
                        color: const Color(0xFF16A34A),
                        onTap: phone.isNotEmpty
                            ? () => _copyPhone(phone)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _driverActionButton(
                        icon: Icons.chat_bubble_rounded,
                        label: "Chat",
                        color: const Color(0xFF2563EB),
                        onTap: () => _showSnack("In-app chat coming soon"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _driverActionButton(
                        icon: Icons.share_rounded,
                        label: "Share",
                        color: const Color(0xFF7C3AED),
                        onTap: () => _shareRide(pickupAddress, dropAddress),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _driverActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyPhone(String phone) {
    Clipboard.setData(ClipboardData(text: phone));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Driver's number copied: $phone"),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _shareRide(String pickup, String drop) {
    final text = "🏍 My ride: $pickup → $drop";
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Ride details copied to clipboard"),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildOffersSection() {
    final currentFare = _formatFareToInt(
        ride?["offeredFare"] ?? ride?["estimatedFare"] ?? ride?["finalFare"]
    );

    return ReflectionCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rideMode == RideMode.negotiation ? "Driver Offers" : "Ride Request",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "Your offer: ₹$currentFare",
                  style: const TextStyle(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (normalModeTimeout) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "No Captains Available",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppPalette.slate900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Captains are busy right now. Please try again.",
                    style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.slate500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      backgroundColor: AppPalette.primary,
                      foregroundColor: AppPalette.navy900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        normalModeTimeout = false;
                      });
                      _startNormalTimeoutTimer();
                      _rebookRide("normal");
                    },
                    child: const Text("Retry"),
                  ),
                ],
              ),
            ),
          ] else ...[
            if (rideMode == RideMode.negotiation) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    color: AppPalette.primary,
                    backgroundColor: AppPalette.primary.withOpacity(0.12),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Waiting for offers - ${_formatCountdown(negotiationSecondsRemaining)} remaining",
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppPalette.primary,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppPalette.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "Finding your captain...",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppPalette.primary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (rideMode == RideMode.normal)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.hourglass_empty_rounded,
                      size: 40,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Finding your captain...",
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Builder(
                builder: (context) {
                  final activeOffers = offers
                      .where((o) => o["status"]?.toString() != "rejected")
                      .toList();
                  final counterAmount = _toDouble(ride?["counterOffer"]) ?? 0;
                  final isCountered =
                      ride?["negotiationStatus"]?.toString() == "countered" &&
                          counterAmount > 0;

                  final List<Map<String, dynamic>> displayOffers =
                      activeOffers.isNotEmpty
                          ? activeOffers
                          : (isCountered
                              ? [
                                  {
                                    "_id": "",
                                    "driverName": (ride?["driverId"] is Map
                                            ? ride!["driverId"]["name"]
                                            : null) ??
                                        "Arun K. (Captain)",
                                    "offeredFare": counterAmount,
                                    "rating": "4.8",
                                    "eta": "~3 min",
                                  }
                                ]
                              : <Map<String, dynamic>>[]);

                  if (displayOffers.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.hourglass_empty_rounded,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            ride?["negotiationStatus"]?.toString() == "rejected"
                                ? "Offer declined. Waiting for another captain..."
                                : "Waiting for driver offers…",
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: displayOffers.map((offer) {
                      final offerId = _normalizeOfferId(offer["_id"]) ?? "";
                      final driverName =
                          offer["driverName"]?.toString() ?? "Arun K. (Captain)";
                      final formattedFare = _formatFareToInt(offer["offeredFare"]);
                      final rating =
                          (offer["driverRating"] ?? offer["rating"])?.toString() ??
                              "4.8";
                      final eta = offer["eta"]?.toString() ?? "~3 min";

                      return _SlideToAcceptOfferCard(
                        key: ValueKey(offerId.isNotEmpty ? offerId : "$driverName-$formattedFare"),
                        driverName: driverName,
                        formattedFare: formattedFare,
                        rating: rating,
                        eta: eta,
                        isDisabled: actionLoading,
                        onAccept: () => _acceptCounterOffer(offer),
                        onDecline: () => _declineOffer(offerId),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  // Deleted _buildNormalWaitingCard

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
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFFFFB4AB),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "No offer was confirmed before the countdown ended. You can start a fresh negotiation or switch to direct booking.",
            style: TextStyle(
              color: Color(0xFFFFDAD6),
              fontWeight: FontWeight.w600,
            ),
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

  Marker _buildCaptainMarker(LatLng point) {
    return Marker(
      point: point,
      width: 44,
      height: 44,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF9800).withValues(alpha: 0.45),
              blurRadius: 12,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.two_wheeler,
            color: Color(0xFF111827),
            size: 22,
          ),
        ),
      ),
    );
  }

  Marker _buildPickupMarker(LatLng point) {
    return Marker(
      point: point,
      width: 44,
      height: 44,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF10B981),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.65),
              blurRadius: 16,
              spreadRadius: 3,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.location_on_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Marker _buildDropMarker(LatLng point) {
    return Marker(
      point: point,
      width: 44,
      height: 44,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE11D48),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE11D48).withValues(alpha: 0.65),
              blurRadius: 16,
              spreadRadius: 3,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.flag_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildMap(String status) {
    final double pickupLat = _toDouble(ride?["pickupLat"]) ?? 0;
    final double pickupLng = _toDouble(ride?["pickupLng"]) ?? 0;
    final double destinationLat =
        _toDouble(ride?["dropLat"] ?? ride?["destinationLat"]) ?? pickupLat;
    final double destinationLng =
        _toDouble(ride?["dropLng"] ?? ride?["destinationLng"]) ?? pickupLng;

    if (_captainLocation == null && ride?["driverId"] is Map) {
      final driverMap = ride!["driverId"] as Map;
      final double? dLat = _toDouble(driverMap["location"]?["lat"]);
      final double? dLng = _toDouble(driverMap["location"]?["lng"]);
      if (dLat != null && dLng != null && dLat != 0.0 && dLng != 0.0) {
        _captainLocation = LatLng(dLat, dLng);
      }
    }

    final rideStatus = ride?["status"]?.toString().toLowerCase() ?? status.toLowerCase();
    final isAcceptedOrArriving = rideStatus == "accepted" || rideStatus == "arriving";
    final isInProgressOrStarted =
        rideStatus == "in_progress" || rideStatus == "started" || rideStatus == "ongoing";

    final pickupLatLng = _pickupLocation ??
        ((pickupLat != 0.0 && pickupLng != 0.0)
            ? LatLng(pickupLat, pickupLng)
            : LatLng(AppConfig.defaultLat, AppConfig.defaultLng));
    final dropLatLng = _dropLocation ??
        ((destinationLat != 0.0 && destinationLng != 0.0)
            ? LatLng(destinationLat, destinationLng)
            : pickupLatLng);

    final LatLng? riderPoint = _riderLiveLocation ??
        ((liveRiderLat != null && liveRiderLng != null)
            ? LatLng(liveRiderLat!, liveRiderLng!)
            : null);

    final routePoints = _liveRoutePoints.isNotEmpty ? _liveRoutePoints : _roadRoutePoints;
    final bool hasRoute = routePoints.length >= 2;

    final LatLng roadDrop = (hasRoute && !isAcceptedOrArriving) ? routePoints.last : dropLatLng;
    final bool isDropOffRoad = hasRoute &&
        !isAcceptedOrArriving &&
        destinationLat != 0.0 &&
        const Distance().as(LengthUnit.Meter, dropLatLng, roadDrop) > 5.0;

    final LatLng? pickupTarget = _pickupLocation ??
        ((pickupLat != 0.0 && pickupLng != 0.0) ? LatLng(pickupLat, pickupLng) : null);

    final bool showWalkingToPickup = !isInProgressOrStarted &&
        rideStatus != "completed" &&
        rideStatus != "cancelled" &&
        riderPoint != null &&
        pickupTarget != null;

    final markers = <Marker>[];

    if (isAcceptedOrArriving) {
      if (_pickupLocation != null) {
        markers.add(_buildPickupMarker(_pickupLocation!));
      }
      if (riderPoint != null) {
        markers.add(
          Marker(
            point: riderPoint,
            width: 76,
            height: 76,
            child: _GoogleMapsRiderPuck(heading: _riderHeading),
          ),
        );
      }
      if (_captainLocation != null) {
        markers.add(_buildCaptainMarker(_captainLocation!));
      }
    } else if (isInProgressOrStarted) {
      if (_dropLocation != null) {
        markers.add(_buildDropMarker(_dropLocation!));
      }
      if (riderPoint != null) {
        markers.add(
          Marker(
            point: riderPoint,
            width: 76,
            height: 76,
            child: _GoogleMapsRiderPuck(heading: _riderHeading),
          ),
        );
      }
      if (_captainLocation != null) {
        markers.add(_buildCaptainMarker(_captainLocation!));
      }
    } else {
      if (_pickupLocation != null) {
        markers.add(_buildPickupMarker(_pickupLocation!));
      }
      if (_dropLocation != null) {
        markers.add(_buildDropMarker(_dropLocation!));
      }
      if (riderPoint != null) {
        markers.add(
          Marker(
            point: riderPoint,
            width: 76,
            height: 76,
            child: _GoogleMapsRiderPuck(heading: _riderHeading),
          ),
        );
      }
      if (_captainLocation != null) {
        markers.add(_buildCaptainMarker(_captainLocation!));
      }
    }

    final validPoints = routePoints.where((p) => p.latitude != 0.0 && p.longitude != 0.0).toList();
    LatLngBounds? bounds = hasRoute
        ? (validPoints.isNotEmpty
            ? LatLngBounds.fromPoints(validPoints)
            : LatLngBounds.fromPoints([pickupLatLng, dropLatLng]))
        : null;
    if (bounds == null && isAcceptedOrArriving && _captainLocation != null && _pickupLocation != null) {
      bounds = LatLngBounds.fromPoints([_captainLocation!, _pickupLocation!]);
    }

    double targetZoom = 14.5;
    LatLng center = LatLng(
      pickupLat != 0.0 ? pickupLat : AppConfig.defaultLat,
      pickupLng != 0.0 ? pickupLng : AppConfig.defaultLng,
    );
    if (bounds != null) {
      final latDiff = (bounds.north - bounds.south).abs();
      final lngDiff = (bounds.east - bounds.west).abs();
      final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
      center = bounds.center;
      if (maxDiff < 0.01) {
        targetZoom = 15.5;
      } else if (maxDiff < 0.04) {
        targetZoom = 14.5;
      } else if (maxDiff < 0.10) {
        targetZoom = 13.5;
      } else if (maxDiff < 0.25) {
        targetZoom = 12.5;
      } else if (maxDiff < 0.60) {
        targetZoom = 11.8;
      } else {
        targetZoom = 11.2;
      }
    }

    final Color activeRouteColor =
        isAcceptedOrArriving ? const Color(0xFF10B981) : const Color(0xFFFF6B00);

    final mapOptions = MapOptions(
      initialCenter: center,
      initialZoom: targetZoom.clamp(11.0, 16.0),
      minZoom: 11.0,
      maxZoom: 18.0,
      onMapReady: () {
        setState(() {
          _isMapReady = true;
        });
        if (isAcceptedOrArriving && _captainLocation != null && _pickupLocation != null) {
          _frameCamera(_captainLocation!, _pickupLocation!);
        } else if (isInProgressOrStarted && _captainLocation != null && _dropLocation != null) {
          _frameCamera(_captainLocation!, _dropLocation!);
        }
      },
    );

    return SizedBox(
      height: 280,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: mapOptions,
              children: [
                ColorFiltered(
                  colorFilter: Theme.of(context).brightness == Brightness.dark
                      ? const ColorFilter.matrix(<double>[
                          -0.2126, -0.7152, -0.0722, 0, 255, // Red channel (inverted + desaturated dark slate)
                          -0.2126, -0.7152, -0.0722, 0, 255, // Green channel
                          -0.2126, -0.7152, -0.0722, 0, 255, // Blue channel
                           0,       0,       0,      1,   0, // Alpha channel
                        ])
                      : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                  child: TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.ridego.bike_taxi_app',
                    maxZoom: 19,
                  ),
                ),
                if (hasRoute || showWalkingToPickup)
                  PolylineLayer(
                    polylines: [
                      if (hasRoute) ...[
                        // Under-glow Polyline (Layer 1)
                        Polyline(
                          points: routePoints,
                          color: activeRouteColor.withValues(alpha: 0.28),
                          strokeWidth: 10.0,
                          strokeCap: StrokeCap.round,
                          strokeJoin: StrokeJoin.round,
                        ),
                        // Main Route Polyline (Layer 2)
                        Polyline(
                          points: routePoints,
                          color: activeRouteColor,
                          strokeWidth: 5.0,
                          strokeCap: StrokeCap.round,
                          strokeJoin: StrokeJoin.round,
                          borderStrokeWidth: 0.0,
                        ),
                        // Drop-off Walking Connector (Dotted)
                        if (isDropOffRoad)
                          Polyline(
                            points: [roadDrop, dropLatLng],
                            color: Colors.white.withValues(alpha: 0.85),
                            strokeWidth: 3.5,
                            strokeCap: StrokeCap.round,
                            pattern: const StrokePattern.dotted(spacingFactor: 1.8),
                          ),
                      ],
                      // Rider Live Location to Pickup Walking Connector (Dotted Cyan)
                      if (showWalkingToPickup && riderPoint != null && pickupTarget != null)
                        Polyline(
                          points: [riderPoint, pickupTarget],
                          color: const Color(0xFF00E5FF),
                          strokeWidth: 3.5,
                          strokeCap: StrokeCap.round,
                          pattern: const StrokePattern.dotted(spacingFactor: 2.2),
                        ),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Live Ride Overview",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                        _buildStatusChip(rideStatus),
                      ],
                    ),
                  ),
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
    final status = ride?["status"]?.toString() ?? "";
    final pickupAddress = readableLocationLabel(
      ride?["pickupAddress"]?.toString() ?? ride?["pickup"]?.toString(),
      fallback: "Pickup address",
    );
    final dropAddress = readableLocationLabel(
      ride?["dropAddress"]?.toString() ?? ride?["destination"]?.toString(),
      fallback: "Drop address",
    );
    final dynamic negotiatedFare = ride?["offeredFare"] ?? ride?["finalFare"];
    final fare = _formatFareToInt(
        negotiatedFare != null && negotiatedFare != 0
            ? negotiatedFare
            : ride?["estimatedFare"]
    );
    final offeredFare = _formatFareToInt(ride?["offeredFare"]);
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
                        padding: EdgeInsets.zero,
                        child: _buildMap(status),
                      ),
                      const SizedBox(height: 20),
                      ReflectionCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Route Details",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.slate900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF16A34A,
                                ).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFF16A34A,
                                  ).withOpacity(0.18),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.my_location_rounded,
                                    color: Color(0xFF16A34A),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Pickup Point",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF16A34A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          pickupAddress,
                                          style: const TextStyle(
                                            fontSize: 13,
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
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFDC2626,
                                ).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFFDC2626,
                                  ).withOpacity(0.18),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.flag_rounded,
                                    color: Color(0xFFDC2626),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Drop Point",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFDC2626),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dropAddress,
                                          style: const TextStyle(
                                            fontSize: 13,
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
                      // Driver assigned card (user view only, when accepted or ongoing)
                      if ((status == "accepted" || status == "ongoing") &&
                          !widget.isDriver &&
                          driverMap != null) ...[
                        _buildDriverAssignedCard(
                          driverMap: Map<String, dynamic>.from(driverMap),
                          otp: ride?["otp"]?.toString() ?? "",
                          fare: fare,
                          pickupAddress: pickupAddress,
                          dropAddress: dropAddress,
                          status: status,
                        ),
                      ],
                      if (isWaiting) ...[
                        _buildOffersSection(),
                        const SizedBox(height: 20),
                      ],
                      if (isNegotiationExpired) ...[
                        _buildExpiredNegotiationCard(),
                        const SizedBox(height: 20),
                      ],
                      ReflectionCard(
                        padding: EdgeInsets.zero,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            initiallyExpanded: false,
                            title: const Text(
                              "Ride Details",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppPalette.slate900,
                              ),
                            ),
                            subtitle: null,
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: (status == "requested" || status == "negotiating" || status == "negotiation_expired")
                                ? []
                                : [
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
                      ),
                      const SizedBox(height: 20),
                      if (!widget.isDriver &&
                          (status == "requested" ||
                           status == "negotiating" ||
                           status == "negotiation_expired")) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: Colors.red.shade900,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 2,
                            ),
                            onPressed: actionLoading ? null : cancelRide,
                            icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.white),
                            label: const Text(
                              "Cancel Ride Request",
                              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
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
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  onPressed: actionLoading
                                      ? null
                                      : startRide,
                                  child: const Text("Verify & Start"),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  onPressed: actionLoading
                                      ? null
                                      : cancelRide,
                                  child: const Text("Cancel"),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4ADE80),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Driver is on the way to your pickup",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.75),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(
                                  color: Colors.redAccent,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: actionLoading
                                  ? null
                                  : cancelRide,
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text(
                                "Cancel Ride",
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],
                      if (status == "ongoing") ...[
                        Row(
                          children: [
                            if (widget.isDriver) ...[
                              Expanded(
                                flex: 3,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    backgroundColor: AppPalette.secondary,
                                  ),
                                  onPressed: actionLoading
                                      ? null
                                      : completeRide,
                                  child: const Text("Complete Ride"),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  onPressed: actionLoading
                                      ? null
                                      : cancelRide,
                                  child: const Text("Cancel"),
                                ),
                              ),
                            ] else ...[
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                  onPressed: actionLoading
                                      ? null
                                      : cancelRide,
                                  child: const Text("Cancel Ride"),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
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
                                  onPressed: () =>
                                      _showUPIQRCodeDialog(context, fare),
                                  child: const Text("Generate QR Code"),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: actionLoading
                                      ? null
                                      : payRide,
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
                                border: Border.all(
                                  color: const Color(0xFF93C5FD),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.payments_rounded,
                                    color: AppPalette.primary,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                              onPressed: () =>
                                  _showRiderUPISelector(context, fare),
                              child: const Text("Pay Now (UPI)"),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(
                                  double.infinity,
                                  54,
                                ),
                                side: const BorderSide(
                                  color: AppPalette.primary,
                                ),
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
                              onPressed: () =>
                                  _processRiderCardPayment(context),
                              child: const Text("Pay Now (Card)"),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(
                                  double.infinity,
                                  54,
                                ),
                                side: const BorderSide(
                                  color: AppPalette.primary,
                                ),
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
                                minimumSize: const Size(
                                  double.infinity,
                                  54,
                                ),
                                side: const BorderSide(
                                  color: AppPalette.primary,
                                ),
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
                        const SizedBox(height: 20),
                      ],
                      if (message.isNotEmpty && message != "Ride fetched successfully") ...[
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

class _GoogleMapsRiderPuck extends StatefulWidget {
  final double heading;

  const _GoogleMapsRiderPuck({required this.heading});

  @override
  State<_GoogleMapsRiderPuck> createState() => _GoogleMapsRiderPuckState();
}

class _GoogleMapsRiderPuckState extends State<_GoogleMapsRiderPuck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double safeHeading =
        (widget.heading.isNaN || widget.heading < 0) ? 0.0 : widget.heading;
    final double headingRadians = safeHeading * (math.pi / 180.0);

    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: headingRadians,
            child: CustomPaint(
              size: const Size(76, 76),
              painter: _HeadingConePainter(),
            ),
          ),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final double haloSize = 30.0 + (_pulseAnimation.value * 14.0);
              return Container(
                width: haloSize,
                height: haloSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF2979FF).withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFF2979FF),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3.0),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2979FF).withValues(alpha: 0.45),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;
    const double sweepAngle = 70 * (math.pi / 180.0);
    const double startAngle = -math.pi / 2 - (sweepAngle / 2);

    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.5,
        colors: [
          const Color(0xFF2979FF).withValues(alpha: 0.55),
          const Color(0xFF2979FF).withValues(alpha: 0.22),
          const Color(0xFF2979FF).withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SlideToAcceptOfferCard extends StatefulWidget {
  final String driverName;
  final String formattedFare;
  final String rating;
  final String eta;
  final bool isDisabled;
  final Future<void> Function() onAccept;
  final VoidCallback onDecline;

  const _SlideToAcceptOfferCard({
    super.key,
    required this.driverName,
    required this.formattedFare,
    required this.rating,
    required this.eta,
    required this.isDisabled,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<_SlideToAcceptOfferCard> createState() => _SlideToAcceptOfferCardState();
}

class _SlideToAcceptOfferCardState extends State<_SlideToAcceptOfferCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _chevronController;
  double _dragX = 0.0;
  bool _acceptedTriggered = false;

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(" ").where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) return "C";
    return parts.map((w) => w[0]).take(2).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initialsFor(widget.driverName);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = constraints.maxWidth;
        const double avatarSize = 48.0;
        const double horizontalPadding = 14.0;
        final double maxDrag =
            (cardWidth - avatarSize - horizontalPadding * 2).clamp(40.0, cardWidth);
        final double acceptThreshold = (cardWidth * 0.68).clamp(40.0, maxDrag);
        final double progress = (_dragX / maxDrag).clamp(0.0, 1.0);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (widget.isDisabled || _acceptedTriggered)
                  ? null
                  : (details) {
                      setState(() {
                        _dragX = (_dragX + details.delta.dx).clamp(0.0, maxDrag);
                      });
                    },
              onHorizontalDragEnd: (widget.isDisabled || _acceptedTriggered)
                  ? null
                  : (_) async {
                      if (_dragX >= acceptThreshold) {
                        setState(() {
                          _acceptedTriggered = true;
                          _dragX = maxDrag;
                        });
                        HapticFeedback.mediumImpact();
                        await widget.onAccept();
                        if (mounted) {
                          setState(() {
                            _acceptedTriggered = false;
                            _dragX = 0.0;
                          });
                        }
                      } else {
                        setState(() {
                          _dragX = 0.0;
                        });
                      }
                    },
              onHorizontalDragCancel: () {
                if (!_acceptedTriggered) {
                  setState(() {
                    _dragX = 0.0;
                  });
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF141820),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _dragX >= acceptThreshold
                        ? const Color(0xFF10B981)
                        : const Color(0xFF10B981).withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Stack(
                  children: [
                    // Low-transparency translucent green overlay across the card
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                const Color(0xFF10B981).withValues(alpha: 0.16),
                                const Color(0xFF10B981).withValues(alpha: 0.14),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Dynamic progressive drag sweep
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: (_dragX + avatarSize + horizontalPadding)
                          .clamp(0.0, cardWidth),
                      child: IgnorePointer(
                        child: Container(
                          color: const Color(0xFF10B981)
                              .withValues(alpha: 0.12 + (progress * 0.18)),
                        ),
                      ),
                    ),
                    // Animated right-moving chevron arrows (>>>)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _chevronController,
                          builder: (context, _) {
                            final t = _chevronController.value;
                            return Align(
                              alignment: Alignment.center,
                              child: Transform.translate(
                                offset: Offset((t * 28.0) - 14.0, 14.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(3, (i) {
                                    final phase = (t - i * 0.22) % 1.0;
                                    final opacity = (0.20 +
                                            0.55 *
                                                (1.0 - (phase - 0.5).abs() * 2.0)
                                                    .clamp(0.0, 1.0))
                                        .clamp(0.15, 0.75);
                                    return Icon(
                                      Icons.chevron_right_rounded,
                                      size: 20,
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: opacity),
                                    );
                                  }),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Foreground crisp captain info + decline X
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: avatarSize),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Opacity(
                              opacity: (1.0 - progress * 0.65).clamp(0.25, 1.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.driverName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        color: Color(0xFFF59E0B),
                                        size: 14,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        widget.rating,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          color: AppPalette.slate700,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Icon(
                                        Icons.access_time_rounded,
                                        color: AppPalette.slate700,
                                        size: 13,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        widget.eta,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                          color: AppPalette.slate700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _dragX >= acceptThreshold
                                        ? "Release to accept"
                                        : "Slide avatar right to accept",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF34D399)
                                          .withValues(alpha: 0.9),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "₹ ${widget.formattedFare}",
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Material(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: (widget.isDisabled || _acceptedTriggered)
                                  ? null
                                  : widget.onDecline,
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Draggable captain initials avatar handle sliding smoothly on top
                    Positioned(
                      left: horizontalPadding + _dragX,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            color: _dragX >= acceptThreshold
                                ? const Color(0xFF10B981)
                                : const Color(0xFF1E293B),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF10B981),
                              width: 2.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.35),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Center(
                            child: _acceptedTriggered
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    initials,
                                    style: TextStyle(
                                      color: _dragX >= acceptThreshold
                                          ? Colors.white
                                          : const Color(0xFF10B981),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ),
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
}

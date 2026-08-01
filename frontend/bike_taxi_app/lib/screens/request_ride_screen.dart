import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/socket_service.dart';
import '../services/routing_service.dart';
import '../theme/premium_ui.dart';
import '../utils/location_display.dart';

enum _BookingPhase { initial, calculating, routeReady }

class RequestRideScreen extends StatefulWidget {
  final String userId;
  final bool isEmbedded;

  const RequestRideScreen({
    super.key,
    required this.userId,
    this.isEmbedded = false,
  });

  @override
  State<RequestRideScreen> createState() => _RequestRideScreenState();
}

class _RequestRideScreenState extends State<RequestRideScreen> with TickerProviderStateMixin {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  Timer? pickupDebounce;
  Timer? dropDebounce;
  List<Map<String, dynamic>> pickupSuggestions = [];
  List<Map<String, dynamic>> dropSuggestions = [];
  String selectedPaymentMethod = "Cash";
  String bookingMode = "normal";
  final TextEditingController _offerController = TextEditingController();

  String pickupInput = "";
  String dropInput = "";
  String? pickupAddress;
  String? pickupPlaceId;
  double? pickupLat;
  double? pickupLng;
  String? dropAddress;
  String? dropPlaceId;
  double? dropLat;
  double? dropLng;

  bool isSearchingPickup = false;
  bool isSearchingDrop = false;
  bool pickupNoResults = false;
  bool dropNoResults = false;
  String? pickupError;
  String? dropError;
  String message = "";
  bool isLoading = false;
  bool isResolvingCurrentLocation = false;
  String? currentLocationMessage;
  double? currentLat;

  List<LatLng> _roadRoutePoints = [];
  double? _apiDistanceKm;
  double? _apiDurationMinutes;
  double? currentLng;
  List<Map<String, dynamic>> availableDrivers = [];
  Timer? _driversPollTimer;

  final MapController _mapController = MapController();
  bool _isMapReady = false;
  bool _pendingFitOnMapReady = false;
  bool _isUserPanning = false;
  bool _isSequenceRunning = false;
  AnimationController? _cameraAnimCtrl;

  double? lastKnownLat;
  double? lastKnownLng;
  bool _hasFocusedInitialLocation = false;
  bool _pendingLocationFocus = false;

  _BookingPhase _phase = _BookingPhase.initial;
  late final AnimationController _routeAnimCtrl;
  late final AnimationController _glassAnimCtrl;
  late final AnimationController _contentAnimCtrl;
  late final DraggableScrollableController _sheetCtrl;

  late final Animation<double> _glassBlur;
  late final Animation<double> _glassOpacity;

  late final Animation<double> _rideTypeAnim;
  late final Animation<double> _fareAnim;
  late final Animation<double> _etaAnim;

  @override
  void initState() {
    super.initState();
    _sheetCtrl = DraggableScrollableController();

    _routeAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

    _glassAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _glassBlur = Tween<double>(begin: 0, end: 14).animate(CurvedAnimation(parent: _glassAnimCtrl, curve: Curves.easeOut));
    _glassOpacity = Tween<double>(begin: 0.88, end: 0.60).animate(CurvedAnimation(parent: _glassAnimCtrl, curve: Curves.easeOut));

    _contentAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _rideTypeAnim = CurvedAnimation(parent: _contentAnimCtrl, curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic));
    _fareAnim = CurvedAnimation(parent: _contentAnimCtrl, curve: const Interval(0.12, 0.55, curve: Curves.easeOutCubic));
    _etaAnim = CurvedAnimation(parent: _contentAnimCtrl, curve: const Interval(0.25, 0.65, curve: Curves.easeOutCubic));

    _startDriversPolling();
    _loadCurrentLocation();

    _loadFromPrefs().then((_) {
      pickupController.addListener(_saveToPrefs);
      destinationController.addListener(_saveToPrefs);
      _offerController.addListener(_saveToPrefs);
    });

    SocketService.listenDriverLocationUpdated((data) {
      if (!mounted) return;
      final driverId = data["driverId"]?.toString();
      final double? lat = data["lat"] is num ? (data["lat"] as num).toDouble() : double.tryParse("${data["lat"]}");
      final double? lng = data["lng"] is num ? (data["lng"] as num).toDouble() : double.tryParse("${data["lng"]}");

      if (driverId != null && lat != null && lng != null) {
        setState(() {
          final index = availableDrivers.indexWhere((d) => d["_id"]?.toString() == driverId);
          if (index != -1) {
            availableDrivers[index]["location"] = {"lat": lat, "lng": lng};
          } else {
            _fetchAvailableDrivers();
          }
        });
      }
    });
  }

  void _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pickup_text', pickupController.text);
      await prefs.setString('pickup_address', pickupAddress ?? '');
      await prefs.setString('pickup_placeId', pickupPlaceId ?? '');
      await prefs.setDouble('pickup_lat', pickupLat ?? 0.0);
      await prefs.setDouble('pickup_lng', pickupLng ?? 0.0);

      await prefs.setString('destination_text', destinationController.text);
      await prefs.setString('destination_address', dropAddress ?? '');
      await prefs.setString('destination_placeId', dropPlaceId ?? '');
      await prefs.setDouble('destination_lat', dropLat ?? 0.0);
      await prefs.setDouble('destination_lng', dropLng ?? 0.0);

      await prefs.setString('offer_fare', _offerController.text);

      if (currentLat != null && currentLng != null && currentLat != 0.0 && currentLng != 0.0) {
        await prefs.setDouble('last_known_lat', currentLat!);
        await prefs.setDouble('last_known_lng', currentLng!);
      }
    } catch (_) {}
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pText = prefs.getString('pickup_text') ?? '';
      final pAddr = prefs.getString('pickup_address') ?? '';
      final pPid = prefs.getString('pickup_placeId') ?? '';
      final pLat = prefs.getDouble('pickup_lat') ?? 0.0;
      final pLng = prefs.getDouble('pickup_lng') ?? 0.0;

      final dText = prefs.getString('destination_text') ?? '';
      final dAddr = prefs.getString('destination_address') ?? '';
      final dPid = prefs.getString('destination_placeId') ?? '';
      final dLat = prefs.getDouble('destination_lat') ?? 0.0;
      final dLng = prefs.getDouble('destination_lng') ?? 0.0;

      final oFare = prefs.getString('offer_fare') ?? '';
      final kLat = prefs.getDouble('last_known_lat') ?? 0.0;
      final kLng = prefs.getDouble('last_known_lng') ?? 0.0;

      if (!mounted) return;

      setState(() {
        if (kLat != 0.0 && kLng != 0.0) {
          lastKnownLat = kLat;
          lastKnownLng = kLng;
        }

        if (pText.isNotEmpty) {
          pickupController.text = pText;
          pickupInput = pText;
          pickupAddress = pAddr.isNotEmpty ? pAddr : null;
          pickupPlaceId = pPid.isNotEmpty ? pPid : null;
          if (pLat != 0.0) pickupLat = pLat;
          if (pLng != 0.0) pickupLng = pLng;
        }

        if (dText.isNotEmpty) {
          destinationController.text = dText;
          dropInput = dText;
          dropAddress = dAddr.isNotEmpty ? dAddr : null;
          dropPlaceId = dPid.isNotEmpty ? dPid : null;
          if (dLat != 0.0) dropLat = dLat;
          if (dLng != 0.0) dropLng = dLng;
        }

        if (oFare.isNotEmpty) {
          _offerController.text = oFare;
        }
      });

      if (!_hasFocusedInitialLocation) {
        _focusCurrentLocationIfAvailable();
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant RequestRideScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEmbedded) {
      _focusCurrentLocationIfAvailable();
    }
  }

  void _focusCurrentLocationIfAvailable({bool forceAnim = false}) {
    final targetLat = (currentLat != null && currentLat != 0.0)
        ? currentLat
        : (lastKnownLat != null && lastKnownLat != 0.0)
            ? lastKnownLat
            : null;
    final targetLng = (currentLng != null && currentLng != 0.0)
        ? currentLng
        : (lastKnownLng != null && lastKnownLng != 0.0)
            ? lastKnownLng
            : null;

    if (targetLat == null || targetLng == null) return;

    if (!_hasFocusedInitialLocation || forceAnim) {
      if (_isMapReady) {
        _animateCameraTo(LatLng(targetLat, targetLng), 15.5);
        _hasFocusedInitialLocation = true;
      } else {
        _pendingLocationFocus = true;
      }
    }
  }

  @override
  void dispose() {
    _stopDriversPolling();
    SocketService.stopListeningDriverLocationUpdated();
    pickupDebounce?.cancel();
    dropDebounce?.cancel();
    pickupController.dispose();
    destinationController.dispose();
    _cameraAnimCtrl?.dispose();
    _routeAnimCtrl.dispose();
    _glassAnimCtrl.dispose();
    _contentAnimCtrl.dispose();
    _sheetCtrl.dispose();
    _offerController.dispose();
    super.dispose();
  }

  void _startDriversPolling() {
    _driversPollTimer?.cancel();
    _fetchAvailableDrivers();
    _driversPollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _fetchAvailableDrivers();
    });
  }

  void _stopDriversPolling() {
    _driversPollTimer?.cancel();
    _driversPollTimer = null;
  }

  Future<void> _fetchAvailableDrivers() async {
    try {
      final response = await ApiService.getDrivers();
      final list = List<Map<String, dynamic>>.from(
        (response["drivers"] as List<dynamic>? ?? const []).whereType<Map>(),
      );
      if (!mounted) return;
      setState(() {
        availableDrivers = list.where((d) {
          if (d["isAvailable"] != true) return false;
          final loc = d["location"];
          if (loc == null) return false;
          final lat = loc["lat"] is num ? (loc["lat"] as num).toDouble() : double.tryParse("${loc["lat"]}");
          final lng = loc["lng"] is num ? (loc["lng"] as num).toDouble() : double.tryParse("${loc["lng"]}");
          if (lat == null || lng == null || lat == 0.0 || lng == 0.0) return false;
          return true;
        }).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadCurrentLocation() async {
    if (isResolvingCurrentLocation) return;
    setState(() {
      isResolvingCurrentLocation = true;
      currentLocationMessage = "Getting your live location...";
    });
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      isResolvingCurrentLocation = false;
      if (pos == null) {
        currentLocationMessage = "Unable to read live location. Please check access permissions.";
        return;
      }
      currentLat = pos["lat"];
      currentLng = pos["lng"];
      lastKnownLat = pos["lat"];
      lastKnownLng = pos["lng"];
      currentLocationMessage = null;
    });
    _saveToPrefs();
    _focusCurrentLocationIfAvailable(forceAnim: true);
  }

  bool get canSubmit => !isLoading && !isSearchingPickup && !isSearchingDrop && !_hasSamePickupAndDrop &&
      _isValidSelectedLocation(input: pickupController.text, address: pickupAddress, lat: pickupLat, lng: pickupLng) &&
      _isValidSelectedLocation(input: destinationController.text, address: dropAddress, lat: dropLat, lng: dropLng);

  bool _isValidLatitude(double v) => v >= -90 && v <= 90;
  bool _isValidLongitude(double v) => v >= -180 && v <= 180;

  bool _isValidSelectedLocation({required String input, required String? address, required double? lat, required double? lng}) =>
      address != null && lat != null && lng != null && input.trim() == address && _isValidLatitude(lat) && _isValidLongitude(lng);

  bool get _hasSamePickupAndDrop {
    if (pickupAddress == null || dropAddress == null || pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) return false;
    return pickupAddress == dropAddress || (pickupLat == dropLat && pickupLng == dropLng);
  }

  double? get _distanceKm {
    if (_apiDistanceKm != null) return _apiDistanceKm;
    if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) return null;
    const double earthRadiusKm = 6371;
    final double dLat = (dropLat! - pickupLat!) * pi / 180;
    final double dLng = (dropLng! - pickupLng!) * pi / 180;
    final double a = (sin(dLat / 2) * sin(dLat / 2)) + cos(pickupLat! * pi / 180) * cos(dropLat! * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return earthRadiusKm * (2 * atan2(sqrt(a), sqrt(1 - a)));
  }

  double? get estimatedFare {
    final distanceKm = _distanceKm;
    if (distanceKm == null) return null;

    const double baseFare = 15;
    const double baseDistanceKm = 1.5;
    const double perKmRate = 9;
    const double aboveTenKmRate = 8;
    const double platformFee = 5;
    const double gstPercent = 5;

    double distanceFare = 0;
    if (distanceKm > baseDistanceKm) {
      final double remaining = distanceKm - baseDistanceKm;
      distanceFare = distanceKm <= 10 ? remaining * perKmRate : (8.5 * perKmRate) + ((distanceKm - 10) * aboveTenKmRate);
    }

    final double subtotal = baseFare + distanceFare;
    final double beforeGst = subtotal + platformFee;
    return (beforeGst + (beforeGst * (gstPercent / 100))).clamp(40, 100000).toDouble();
  }

  String get _etaText {
    if (_apiDurationMinutes != null) {
      return "${_apiDurationMinutes!.ceil()} min";
    }
    final km = _distanceKm;
    if (km == null) return "--";
    return "${(km / 25 * 60).ceil()} min";
  }

  Future<void> _fetchRoadRoute() async {
    if (pickupLat == null || pickupLng == null || dropLat == null || dropLng == null) return;
    try {
      final result = await RoutingService.getRoute(pickupLat!, pickupLng!, dropLat!, dropLng!);
      if (result != null) {
        setState(() {
          _roadRoutePoints = result.points;
          _apiDistanceKm = result.distanceKm;
          _apiDurationMinutes = result.durationMinutes;
        });
      } else {
        setState(() {
          _roadRoutePoints = [LatLng(pickupLat!, pickupLng!), LatLng(dropLat!, dropLng!)];
          _apiDistanceKm = null;
          _apiDurationMinutes = null;
        });
      }
    } catch (e) {
      setState(() {
        _roadRoutePoints = [LatLng(pickupLat!, pickupLng!), LatLng(dropLat!, dropLng!)];
        _apiDistanceKm = null;
        _apiDurationMinutes = null;
      });
    }
  }

  LatLng? _getBestUserLocation() {
    final lat = pickupLat ?? currentLat ?? lastKnownLat;
    final lng = pickupLng ?? currentLng ?? lastKnownLng;
    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      return LatLng(lat, lng);
    }
    return null;
  }

  LatLng? _getNearestDriverLocation(LatLng userLoc) {
    if (availableDrivers.isEmpty) return null;
    LatLng? nearest;
    double minDistance = double.infinity;

    for (final driver in availableDrivers) {
      if (driver["isAvailable"] != true) continue;
      final loc = driver["location"];
      if (loc == null) continue;
      final double? dLat = loc["lat"] is num ? (loc["lat"] as num).toDouble() : double.tryParse("${loc["lat"]}");
      final double? dLng = loc["lng"] is num ? (loc["lng"] as num).toDouble() : double.tryParse("${loc["lng"]}");
      if (dLat == null || dLng == null || dLat == 0.0 || dLng == 0.0) continue;

      final dist = (dLat - userLoc.latitude) * (dLat - userLoc.latitude) +
          (dLng - userLoc.longitude) * (dLng - userLoc.longitude);
      if (dist < minDistance) {
        minDistance = dist;
        nearest = LatLng(dLat, dLng);
      }
    }
    return nearest;
  }

  void _fitUserAndDriverOrFocusUser({bool force = false}) {
    if (!_isMapReady || !mounted) return;
    if (_isUserPanning && !force) return;

    final userLoc = _getBestUserLocation();
    if (userLoc == null) return;

    final driverLoc = _getNearestDriverLocation(userLoc);

    if (driverLoc != null) {
      // Driver location available: Smoothly fit User + Driver
      try {
        final bounds = LatLngBounds.fromPoints([userLoc, driverLoc]);

        double bottomPixelPadding = 200.0;
        if (_sheetCtrl.isAttached) {
          final screenHeight = MediaQuery.of(context).size.height;
          bottomPixelPadding = (screenHeight * _sheetCtrl.size) + 40.0;
        } else if (_phase == _BookingPhase.routeReady) {
          bottomPixelPadding = 300.0;
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isMapReady) {
            try {
              final cameraFit = CameraFit.bounds(
                bounds: bounds,
                padding: EdgeInsets.only(
                  top: 100.0,
                  bottom: bottomPixelPadding,
                  left: 48.0,
                  right: 48.0,
                ),
                maxZoom: 16.5,
                minZoom: 12.5,
              );
              final targetCenter = cameraFit.fit(_mapController.camera).center;
              final targetZoom = cameraFit.fit(_mapController.camera).zoom;
              _animateCameraTo(targetCenter, targetZoom);
            } catch (_) {
              _animateCameraTo(userLoc, 15.5);
            }
          }
        });
      } catch (_) {
        _animateCameraTo(userLoc, 15.5);
      }
    } else {
      // Driver location not available: Focus on User's current location at zoom 15.5
      _animateCameraTo(userLoc, 15.5);
    }
  }

  Future<void> _startRouteSequence({bool focusDrop = true}) async {
    if (!mounted) return;
    if (_isSequenceRunning) return;
    _isSequenceRunning = true;

    try {
      setState(() {
        _phase = _BookingPhase.calculating;
      });

      await _fetchRoadRoute();

      if (!mounted) return;

      setState(() {
        _phase = _BookingPhase.routeReady;
        _isUserPanning = false;
      });

      // Fit User + Driver bounds if driver exists, otherwise stay focused on User
      _fitUserAndDriverOrFocusUser(force: true);

      if (_sheetCtrl.isAttached) {
        _sheetCtrl.animateTo(0.60, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
      _contentAnimCtrl.reset();
      _contentAnimCtrl.forward();
    } finally {
      _isSequenceRunning = false;
    }
  }

  void _resetRouteSequence() {
    _routeAnimCtrl.reset();
    _glassAnimCtrl.reset();
    _contentAnimCtrl.reset();
    setState(() {
      _phase = _BookingPhase.initial;
      _isUserPanning = false;
    });
    if (_sheetCtrl.isAttached) {
      _sheetCtrl.animateTo(0.30, duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
    }
  }

  void _animateCameraTo(LatLng targetCenter, double targetZoom) {
    if (!_isMapReady || !mounted) return;
    _cameraAnimCtrl?.stop();
    _cameraAnimCtrl?.dispose();

    final startCenter = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;

    _cameraAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    final anim = CurvedAnimation(parent: _cameraAnimCtrl!, curve: Curves.fastOutSlowIn);

    _cameraAnimCtrl!.addListener(() {
      if (!mounted || !_isMapReady) return;
      final lat = startCenter.latitude + (targetCenter.latitude - startCenter.latitude) * anim.value;
      final lng = startCenter.longitude + (targetCenter.longitude - startCenter.longitude) * anim.value;
      final zoom = startZoom + (targetZoom - startZoom) * anim.value;
      try {
        _mapController.move(LatLng(lat, lng), zoom);
      } catch (_) {}
    });

    _cameraAnimCtrl!.forward();
  }

  void _fitMapToRoute({bool force = false}) {
    if (!_isMapReady) {
      _pendingFitOnMapReady = true;
      return;
    }

    if (_isUserPanning && !force) return;

    final safeCurrentLat = (currentLat != null && currentLat != 0.0) ? currentLat : null;
    final safeCurrentLng = (currentLng != null && currentLng != 0.0) ? currentLng : null;

    if (pickupLat == null || dropLat == null || pickupLat == 0.0 || dropLat == 0.0 || pickupLng == 0.0 || dropLng == 0.0) {
      final activeLat = dropLat ?? pickupLat ?? safeCurrentLat ?? 11.0168;
      final activeLng = dropLng ?? pickupLng ?? safeCurrentLng ?? 76.9558;
      _animateCameraTo(LatLng(activeLat, activeLng), 16.0);
      return;
    }

    if (pickupLat == dropLat && pickupLng == dropLng) {
      _animateCameraTo(LatLng(pickupLat!, pickupLng!), 16.0);
      return;
    }

    try {
      final List<LatLng> pointsToFrame = (_roadRoutePoints.length >= 2)
          ? _roadRoutePoints
          : [LatLng(pickupLat!, pickupLng!), LatLng(dropLat!, dropLng!)];

      final bounds = LatLngBounds.fromPoints(pointsToFrame);

      double bottomPixelPadding = 200.0;
      if (_sheetCtrl.isAttached) {
        final screenHeight = MediaQuery.of(context).size.height;
        bottomPixelPadding = (screenHeight * _sheetCtrl.size) + 40.0;
      } else if (_phase == _BookingPhase.routeReady) {
        bottomPixelPadding = 300.0;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isMapReady) {
          try {
            final cameraFit = CameraFit.bounds(
              bounds: bounds,
              padding: EdgeInsets.only(
                top: 100.0,
                bottom: bottomPixelPadding,
                left: 48.0,
                right: 48.0,
              ),
              maxZoom: 17.0,
              minZoom: 11.0,
            );
            final targetCenter = cameraFit.fit(_mapController.camera).center;
            final targetZoom = cameraFit.fit(_mapController.camera).zoom;
            _animateCameraTo(targetCenter, targetZoom);
          } catch (_) {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: EdgeInsets.only(
                  top: 100.0,
                  bottom: bottomPixelPadding,
                  left: 48.0,
                  right: 48.0,
                ),
                maxZoom: 17.0,
                minZoom: 11.0,
              ),
            );
          }
        }
      });
    } catch (_) {
      _animateCameraTo(LatLng(dropLat!, dropLng!), 15.5);
    }
  }

  void _moveCameraSafely(LatLng center, double zoom) {
    if (_isUserPanning) return;
    _animateCameraTo(center, zoom);
  }

  void _clearPickupSelection() {
    pickupAddress = null;
    pickupPlaceId = null;
    pickupLat = null;
    pickupLng = null;
    pickupError = pickupInput.trim().isEmpty ? null : "Search and select a pickup result";
    _resetRouteSequence();
  }

  void _clearDropSelection() {
    dropAddress = null;
    dropPlaceId = null;
    dropLat = null;
    dropLng = null;
    dropError = dropInput.trim().isEmpty ? null : "Search and select a drop result";
    _resetRouteSequence();
  }

  void _onPickupChanged(String value) {
    pickupInput = value;
    setState(() {
      message = "";
      pickupNoResults = false;
      if (value.trim() != pickupAddress) {
        _clearPickupSelection();
        pickupSuggestions = [];
      } else {
        pickupError = null;
      }
    });
    pickupDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        isSearchingPickup = false;
        pickupSuggestions = [];
      });
      return;
    }
    pickupDebounce = Timer(const Duration(milliseconds: 500), () => _searchPlaces(isPickup: true));
  }

  void _onDropChanged(String value) {
    dropInput = value;
    setState(() {
      message = "";
      dropNoResults = false;
      if (value.trim() != dropAddress) {
        _clearDropSelection();
        dropSuggestions = [];
      } else {
        dropError = null;
      }
    });
    dropDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        isSearchingDrop = false;
        dropSuggestions = [];
      });
      return;
    }
    dropDebounce = Timer(const Duration(milliseconds: 500), () => _searchPlaces(isPickup: false));
  }

  Future<void> _searchPlaces({required bool isPickup}) async {
    final query = isPickup ? pickupController.text.trim() : destinationController.text.trim();
    if (query.length < 3) {
      setState(() {
        if (isPickup) {
          pickupError = "Enter at least 3 characters to search";
          pickupSuggestions = [];
        } else {
          dropError = "Enter at least 3 characters to search";
          dropSuggestions = [];
        }
      });
      return;
    }
    setState(() {
      message = "";
      if (isPickup) {
        isSearchingPickup = true;
        pickupError = null;
        pickupNoResults = false;
      } else {
        isSearchingDrop = true;
        dropError = null;
        dropNoResults = false;
      }
    });
    try {
      final results = await ApiService.searchPhotonPlaces(
        query,
        lat: pickupLat ?? currentLat,
        lng: pickupLng ?? currentLng,
      );
      if (!mounted) return;
      setState(() {
        if (isPickup) {
          isSearchingPickup = false;
          pickupSuggestions = results;
          pickupNoResults = results.isEmpty;
        } else {
          isSearchingDrop = false;
          dropSuggestions = results;
          dropNoResults = results.isEmpty;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isSearchingPickup = false;
        isSearchingDrop = false;
        pickupSuggestions = [];
        dropSuggestions = [];
        message = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  void _selectSuggestion(Map<String, dynamic> suggestion, {required bool isPickup}) {
    final placeId = suggestion["placeId"]?.toString() ?? "";
    final rawAddress = suggestion["address"]?.toString() ?? "";
    final address = readableLocationLabel(rawAddress, fallback: isPickup ? "Pickup address" : "Drop address");
    final lat = suggestion["lat"] is num ? (suggestion["lat"] as num).toDouble() : double.tryParse("${suggestion["lat"]}");
    final lng = suggestion["lng"] is num ? (suggestion["lng"] as num).toDouble() : double.tryParse("${suggestion["lng"]}");

    if (placeId.isEmpty || address.isEmpty || lat == null || lng == null) {
      setState(() => message = "Unable to use the selected place");
      return;
    }
    setState(() {
      message = "";
      if (isPickup) {
        pickupController.text = address;
        pickupInput = address;
        pickupAddress = address;
        pickupPlaceId = placeId;
        pickupLat = lat;
        pickupLng = lng;
        pickupError = null;
        pickupSuggestions = [];
      } else {
        destinationController.text = address;
        dropInput = address;
        dropAddress = address;
        dropPlaceId = placeId;
        dropLat = lat;
        dropLng = lng;
        dropError = null;
        dropSuggestions = [];
      }
      if (_hasSamePickupAndDrop) {
        pickupError = "Pickup location must be different from drop";
        dropError = "Drop location must be different from pickup";
      } else if (pickupLat != null && dropLat != null && pickupLat != 0.0 && dropLat != 0.0) {
        _roadRoutePoints = [LatLng(pickupLat!, pickupLng!), LatLng(dropLat!, dropLng!)];
      }
    });

    if (pickupLat != null && dropLat != null && pickupLat != 0.0 && dropLat != 0.0 && !_hasSamePickupAndDrop) {
      _startRouteSequence(focusDrop: !isPickup);
    } else {
      _fitMapToRoute();
    }
    _saveToPrefs();
  }

  void _onMapTapped(LatLng point) {
    if (pickupLat == null || pickupLng == null) {
      const label = "Resolving pickup address...";
      setState(() {
        pickupLat = point.latitude;
        pickupLng = point.longitude;
        pickupAddress = label;
        pickupController.text = label;
        pickupInput = label;
        pickupPlaceId = "map_tap_pickup";
        pickupError = null;
        message = "Finding pickup address...";
        if (dropLat != null && dropLat != 0.0) {
          _roadRoutePoints = [LatLng(pickupLat!, pickupLng!), LatLng(dropLat!, dropLng!)];
        }
      });
      if (dropLat != null && dropLat != 0.0 && !_hasSamePickupAndDrop) {
        _startRouteSequence(focusDrop: false);
      } else {
        _fitMapToRoute();
      }
      _reverseGeocodeAndUpdate(point.latitude, point.longitude, isPickup: true, fallbackAddress: "Pickup address from map");
    } else {
      const label = "Resolving drop address...";
      setState(() {
        dropLat = point.latitude;
        dropLng = point.longitude;
        dropAddress = label;
        destinationController.text = label;
        dropInput = label;
        dropPlaceId = "map_tap_drop";
        dropError = null;
        message = "Finding drop address...";
        if (pickupLat != null && pickupLat != 0.0) {
          _roadRoutePoints = [LatLng(pickupLat!, pickupLng!), LatLng(dropLat!, dropLng!)];
        }
      });
      if (pickupLat != null && pickupLat != 0.0 && !_hasSamePickupAndDrop) {
        _startRouteSequence(focusDrop: true);
      } else {
        if (dropLat != null && dropLng != null) {
          _animateCameraTo(LatLng(dropLat!, dropLng!), 15.5);
        }
      }
      _reverseGeocodeAndUpdate(point.latitude, point.longitude, isPickup: false, fallbackAddress: "Drop address from map");
    }
  }

  Future<void> _reverseGeocodeAndUpdate(double lat, double lng, {required bool isPickup, required String fallbackAddress}) async {
    var nextAddress = fallbackAddress;
    try {
      final result = await ApiService.reversePhotonPlace(lat, lng);
      if (!mounted) return;
      final bestAddress = result?["address"]?.toString();
      if (bestAddress != null && bestAddress.isNotEmpty) {
        nextAddress = readableLocationLabel(bestAddress, fallback: fallbackAddress);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      if (isPickup) {
        pickupAddress = nextAddress;
        pickupController.text = nextAddress;
        pickupInput = nextAddress;
        pickupError = null;
      } else {
        dropAddress = nextAddress;
        destinationController.text = nextAddress;
        dropInput = nextAddress;
        dropError = null;
      }
    });

    if (!isPickup && dropLat != null && dropLng != null && dropLat != 0.0 && dropLng != 0.0) {
      _animateCameraTo(LatLng(dropLat!, dropLng!), 15.5);
    }
    _saveToPrefs();
  }

  Future<void> _selectCurrentPickupAddress(Map<String, double> pos) async {
    final lat = pos['lat'] ?? currentLat ?? lastKnownLat;
    final lng = pos['lng'] ?? currentLng ?? lastKnownLng;

    if (lat == null || lng == null || lat == 0.0 || lng == 0.0) return;

    _selectSuggestion({
      "placeId": "gps_current_loc",
      "address": "Resolving current address...",
      "lat": lat,
      "lng": lng,
    }, isPickup: true);

    // Smoothly animate map camera to current location at zoom 15.5
    _animateCameraTo(LatLng(lat, lng), 15.5);

    await _reverseGeocodeAndUpdate(lat, lng, isPickup: true, fallbackAddress: "Current pickup address");
  }

  // FIXED: Send the negotiated fare if in negotiation mode & log errors
  void _requestRide() async {
    if (!canSubmit) {
      setState(() {
        pickupError = _isValidSelectedLocation(input: pickupController.text, address: pickupAddress, lat: pickupLat, lng: pickupLng)
            ? null : "Search and select a valid pickup location";
        dropError = _isValidSelectedLocation(input: destinationController.text, address: dropAddress, lat: dropLat, lng: dropLng)
            ? null : "Search and select a valid drop location";
        message = "Pick a valid route matrix configuration before requesting deployment.";
      });
      return;
    }
    // DELAYED ROUTE FIT: Perform full route camera fit when confirming ride
    _fitMapToRoute(force: true);
    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      double finalFare = estimatedFare ?? 0;
      if (bookingMode == "negotiation" && _offerController.text.trim().isNotEmpty) {
        finalFare = double.tryParse(_offerController.text.trim()) ?? finalFare;
      }

      final response = await ApiService.requestRide(
        widget.userId, pickupAddress!, pickupLat!, pickupLng!, dropAddress!, dropLat!, dropLng!,
        selectedPaymentMethod, pickupPlaceId, dropPlaceId, bookingMode, finalFare,
      );
      if (!mounted) return;
      if (response["ride"] != null && response["ride"]["_id"] != null) {
        context.go('/ride-status/${response["ride"]["_id"]}');
      }
    } catch (e) {
      debugPrint("API Failure in _requestRide: $e");
      if (!mounted) return;
      String errMessage = e.toString().replaceFirst("Exception: ", "");
      if (errMessage.toLowerCase().contains("no drivers available")) {
        errMessage = "No dispatch resources currently available. Please re-attempt shortly.";
      }
      setState(() => message = errMessage);
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showFareBreakdown() {
    final double? fare = estimatedFare;
    if (fare == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ReflectionCard(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Fare Breakdown", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppPalette.slate900)),
            const SizedBox(height: 16),
            _fareRow("Base Rate Breakdown", "₹ 40.00"),
            const SizedBox(height: 10),
            _fareRow("Distance Computations", "₹ ${((fare - 40).clamp(0, 100000)).round().toStringAsFixed(2)}"),
            const Divider(height: 24),
            _fareRow("Total Invoiced Estimate", "₹ ${fare.round().toStringAsFixed(2)}", isTotal: true),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Acknowledge")),
          ],
        ),
      ),
    );
  }

  Widget _fareRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600, fontSize: isTotal ? 16 : 14, color: isTotal ? AppPalette.slate900 : AppPalette.slate600)),
        Text(value, style: TextStyle(fontWeight: isTotal ? FontWeight.w900 : FontWeight.w800, fontSize: isTotal ? 18 : 14, color: isTotal ? AppPalette.primary : AppPalette.slate900)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    return widget.isEmbedded ? body : Scaffold(backgroundColor: const Color(0xFF141616), body: body);
  }

  Widget _buildBody(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final sheetOffset = _sheetCtrl.isAttached ? MediaQuery.of(context).size.height * _sheetCtrl.size : 220.0;
    return Stack(
      children: [
        _buildFullScreenMap(),
        Positioned(top: topPadding + 8, left: 16, right: 16, child: _buildFloatingBrandHeader()),
        Positioned(top: topPadding + 78, left: 16, right: 16, child: _buildFloatingLocationCard()),
        if (_phase == _BookingPhase.calculating)
          Positioned(bottom: MediaQuery.of(context).size.height * 0.25 + 8, left: 0, right: 0, child: Center(child: _buildCalculatingPill())),
        if (_isUserPanning || _phase == _BookingPhase.routeReady)
          Positioned(
            bottom: sheetOffset + 16,
            right: 16,
            child: _buildRecenterButton(),
          ),
        _buildDraggableSheet(context),
      ],
    );
  }

  Widget _buildRecenterButton() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF141616).withOpacity(0.85),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: IconButton(
            tooltip: "Recenter Map Focus",
            icon: const Icon(Icons.my_location_rounded, color: Color(0xFFF4A261), size: 22),
            onPressed: () {
              setState(() {
                _isUserPanning = false;
              });
              _fitMapToRoute(force: true);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBrandHeader() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF141616).withOpacity(0.75),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.11)),
          ),
          child: const Center(
            child: Text("Dot Taxi", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.6)),
          ),
        ),
      ),
    );
  }

  // FIXED: Strictly filter offline drivers and invalid locations
  Widget _buildFullScreenMap() {
    final initialCenter = (currentLat != null && currentLng != null && currentLat != 0.0 && currentLng != 0.0)
        ? LatLng(currentLat!, currentLng!)
        : (lastKnownLat != null && lastKnownLng != null && lastKnownLat != 0.0 && lastKnownLng != 0.0)
            ? LatLng(lastKnownLat!, lastKnownLng!)
            : const LatLng(11.0168, 76.9558);

    final driverMarkers = availableDrivers.where((driver) {
      if (driver["isAvailable"] != true) return false;
      final loc = driver["location"];
      if (loc == null) return false;
      final double? lat = loc["lat"] is num ? (loc["lat"] as num).toDouble() : double.tryParse("${loc["lat"]}");
      final double? lng = loc["lng"] is num ? (loc["lng"] as num).toDouble() : double.tryParse("${loc["lng"]}");
      if (lat == null || lng == null || lat == 0.0 || lng == 0.0) return false;
      return true;
    }).map((driver) {
      final loc = driver["location"];
      final double lat = loc["lat"] is num ? (loc["lat"] as num).toDouble() : double.parse("${loc["lat"]}");
      final double lng = loc["lng"] is num ? (loc["lng"] as num).toDouble() : double.parse("${loc["lng"]}");
      return Marker(
        point: LatLng(lat, lng),
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppPalette.primary, width: 2)),
          child: const Icon(Icons.directions_bike_rounded, color: AppPalette.primary, size: 18),
        ),
      );
    }).toList();

    List<LatLng> polylinePoints = [];
    if (pickupLat != null && dropLat != null && pickupLat != 0.0 && dropLat != 0.0 && pickupLng != 0.0 && dropLng != 0.0) {
      polylinePoints = _roadRoutePoints.isNotEmpty
          ? _roadRoutePoints
          : [LatLng(pickupLat!, pickupLng!), LatLng(dropLat!, dropLng!)];
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 15.5,
        minZoom: 11.0, 
        maxZoom: 18.0,
        onTap: (_, point) => _onMapTapped(point),
        onPositionChanged: (position, hasGesture) {
          if (hasGesture && !_isUserPanning) {
            setState(() {
              _isUserPanning = true;
            });
          }
        },
        onMapReady: () {
          setState(() {
            _isMapReady = true;
          });
          if (_pendingLocationFocus || !_hasFocusedInitialLocation) {
            _pendingLocationFocus = false;
            _focusCurrentLocationIfAvailable(forceAnim: true);
          } else if (_pendingFitOnMapReady) {
            _pendingFitOnMapReady = false;
            _fitMapToRoute(force: true);
          }
        },
      ),
      children: [
        TileLayer(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", userAgentPackageName: "com.example.bike_taxi_app"),
        if (polylinePoints.length >= 2)
          PolylineLayer(polylines: [Polyline(points: polylinePoints, color: const Color(0xFFF4A261), strokeWidth: 5.0, borderColor: Colors.white.withOpacity(0.4), borderStrokeWidth: 2.0)]),
        MarkerLayer(markers: [
          ...driverMarkers,
          if (currentLat != null && currentLng != null && currentLat != 0.0 && currentLng != 0.0 && pickupLat == null) Marker(point: LatLng(currentLat!, currentLng!), width: 48, height: 48, child: const Icon(Icons.my_location_rounded, size: 36, color: Color(0xFF16A34A))),
          if (pickupLat != null && pickupLat != 0.0) Marker(point: LatLng(pickupLat!, pickupLng!), width: 48, height: 48, child: const Icon(Icons.my_location_rounded, size: 36, color: Color(0xFF16A34A))),
          if (dropLat != null && dropLat != 0.0) Marker(point: LatLng(dropLat!, dropLng!), width: 48, height: 48, child: const Icon(Icons.flag_rounded, size: 36, color: Color(0xFFDC2626))),
        ]),
      ],
    );
  }

  Widget _buildFloatingLocationCard() {
    return AnimatedBuilder(
      animation: _glassAnimCtrl,
      builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _glassBlur.value, sigmaY: _glassBlur.value),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1C1C).withOpacity(_glassOpacity.value),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: child,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCompactLocationField(controller: pickupController, hintText: "Pickup location", onChanged: _onPickupChanged, isSearching: isSearchingPickup, icon: Icons.my_location_rounded, iconColor: const Color(0xFF16A34A), isSelected: pickupAddress != null),
            if (pickupAddress == null && currentLat != null && currentLng != null) _buildCurrentLocationTile(),
            _buildInlineSuggestions(pickupSuggestions, isPickup: true),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(children: [Container(width: 1.5, height: 16, margin: const EdgeInsets.only(left: 13), color: Colors.white.withOpacity(0.18))]),
            ),
            _buildCompactLocationField(controller: destinationController, hintText: "Where to?", onChanged: _onDropChanged, isSearching: isSearchingDrop, icon: Icons.flag_rounded, iconColor: const Color(0xFFDC2626), isSelected: dropAddress != null),
            _buildInlineSuggestions(dropSuggestions, isPickup: false),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentLocationTile() {
    return GestureDetector(
      onTap: isResolvingCurrentLocation ? null : () async {
        Map<String, double>? initialPos;
        if (currentLat != null && currentLng != null && currentLat != 0.0 && currentLng != 0.0) {
          initialPos = {'lat': currentLat!, 'lng': currentLng!};
        } else if (lastKnownLat != null && lastKnownLng != null && lastKnownLat != 0.0 && lastKnownLng != 0.0) {
          initialPos = {'lat': lastKnownLat!, 'lng': lastKnownLng!};
        }

        if (initialPos != null) {
          await _selectCurrentPickupAddress(initialPos);
        }

        final freshPos = await LocationService.getCurrentPosition();
        if (freshPos != null && mounted) {
          setState(() {
            currentLat = freshPos['lat'];
            currentLng = freshPos['lng'];
            lastKnownLat = freshPos['lat'];
            lastKnownLng = freshPos['lng'];
          });
          _saveToPrefs();
          await _selectCurrentPickupAddress(freshPos);
        }
      },
      child: Container(
        height: 52,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: const Color(0xFFF4A261).withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF4A261).withOpacity(0.18))),
        child: Row(
          children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(color: const Color(0xFFF4A261).withOpacity(0.13), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.gps_fixed_rounded, size: 16, color: Color(0xFFF4A261))),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Current Location", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                Text("Use Live GPS Syncing", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.45))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactLocationField({required TextEditingController controller, required String hintText, required ValueChanged<String> onChanged, required bool isSearching, required IconData icon, required Color iconColor, required bool isSelected}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white.withOpacity(isSelected ? 0.10 : 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: isSelected ? iconColor.withOpacity(0.4) : Colors.white.withOpacity(0.08))),
      child: Row(
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Icon(icon, size: 18, color: iconColor)),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              decoration: InputDecoration(hintText: hintText, hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
          if (isSearching) Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: iconColor.withOpacity(0.8)))),
          if (!isSearching && controller.text.isNotEmpty) GestureDetector(onTap: () { controller.clear(); onChanged(""); }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.close_rounded, size: 16, color: Colors.white.withOpacity(0.4)))),
        ],
      ),
    );
  }

  Widget _buildInlineSuggestions(List<Map<String, dynamic>> suggestions, {required bool isPickup}) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(color: const Color(0xFF1A1C1C), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(0.06)),
        itemBuilder: (context, i) {
          final s = suggestions[i];
          return ListTile(
            dense: true,
            leading: Icon(isPickup ? Icons.my_location_rounded : Icons.flag_circle_rounded, size: 18, color: isPickup ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
            title: Text(s["address"]?.toString() ?? "", maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            onTap: () => _selectSuggestion(s, isPickup: isPickup),
          );
        },
      ),
    );
  }

  Widget _buildCalculatingPill() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: const Color(0xFF1A1C1C).withOpacity(0.80), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(0.10))),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: Color(0xFFF4A261))),
              SizedBox(width: 10),
              Text("Analyzing optimal routes…", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDraggableSheet(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetCtrl,
      initialChildSize: 0.30,
      minChildSize: 0.22,
      maxChildSize: 0.90,
      snap: true,
      snapSizes: const [0.30, 0.60, 0.90],
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141616).withOpacity(0.92), 
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)), 
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                _buildSheetContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(2)))),
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text("Booking Mode", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.45), letterSpacing: 0.4))),
        _buildSegmentedControl(),
        const SizedBox(height: 12),
        _buildStaggered(_rideTypeAnim, _buildRideTypeRow()),
        _buildStaggered(_etaAnim, _buildEtaDistanceRow()),
        _buildStaggered(
          _fareAnim,
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: KeyedSubtree(
              key: ValueKey(bookingMode),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: bookingMode == "normal"
                    ? [_buildFareRow(), _buildPaymentRow(), _buildBookButton()]
                    : [_buildSuggestedFareRow(), _buildNegotiationInfoCard(), _buildPaymentRow(), _buildNegotiateFareButton()],
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: message.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(message),
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
                    child: Row(children: [const Icon(Icons.info_outline_rounded, color: Color(0xFFF4A261), size: 18), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)))]),
                  ),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStaggered(Animation<double> anim, Widget child) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        if (anim.value == 0) return const SizedBox.shrink();
        return Opacity(opacity: anim.value.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 16 * (1.0 - anim.value)), child: child));
      },
    );
  }

  Widget _buildSegmentedControl() {
    final isNormal = bookingMode == "normal";
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: isNormal ? 0.0 : 1.0, end: isNormal ? 0.0 : 1.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      builder: (context, t, _) => Container(
        height: 46,
        decoration: BoxDecoration(color: const Color(0xFF0D0F0F), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withOpacity(0.08))),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Align(
                  alignment: Alignment(-1.0 + t * 2.0, 0),
                  child: FractionallySizedBox(widthFactor: 0.5, child: Container(decoration: BoxDecoration(color: const Color(0xFFF4A261), borderRadius: BorderRadius.circular(999)))),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => bookingMode = "normal"),
                    child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.flash_on_rounded, size: 15, color: t < 0.5 ? Colors.black87 : Colors.white.withOpacity(0.45)), const SizedBox(width: 5), Text("Normal", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t < 0.5 ? Colors.black87 : Colors.white.withOpacity(0.45)))]))
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => bookingMode = "negotiation"),
                    child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.handshake_rounded, size: 15, color: t >= 0.5 ? Colors.black87 : Colors.white.withOpacity(0.45)), const SizedBox(width: 5), Text("Negotiate", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: t >= 0.5 ? Colors.black87 : Colors.white.withOpacity(0.45)))]))
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideTypeRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Ride Type", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
          const SizedBox(height: 8),
          Row(children: [_rideTypeChip(Icons.directions_bike_rounded, "Bike", true)]),
        ],
      ),
    );
  }

  Widget _rideTypeChip(IconData icon, String label, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: selected ? const Color(0xFFF4A261).withOpacity(0.14) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? const Color(0xFFF4A261).withOpacity(0.5) : Colors.white.withOpacity(0.08))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16, color: selected ? const Color(0xFFF4A261) : Colors.white.withOpacity(0.5)), const SizedBox(width: 6), Text(label, style: TextStyle(color: selected ? const Color(0xFFF4A261) : Colors.white70, fontWeight: FontWeight.w700, fontSize: 13))],
      ),
    );
  }

  Widget _buildFareRow() {
    final fare = estimatedFare;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.08))),
        child: Row(
          children: [
            const Icon(Icons.currency_rupee_rounded, color: Color(0xFFF4A261), size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Estimated Fare", style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600)),
                  Text(fare != null ? "₹ ${fare.round().toStringAsFixed(2)}" : "--", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                ],
              ),
            ),
            GestureDetector(
              onTap: fare != null ? _showFareBreakdown : null,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFF4A261).withOpacity(0.12), borderRadius: BorderRadius.circular(10)), child: const Text("Breakdown", style: TextStyle(color: Color(0xFFF4A261), fontWeight: FontWeight.w800, fontSize: 12))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEtaDistanceRow() {
    final km = _distanceKm;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: _infoTile(Icons.access_time_rounded, "ETA", _etaText)),
          const SizedBox(width: 10),
          Expanded(child: _infoTile(Icons.straighten_rounded, "Distance", km != null ? "${km.toStringAsFixed(1)} km" : "--")),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFF4A261)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  static const _paymentOptions = [
    {"label": "Cash", "icon": Icons.money_rounded},
    {"label": "UPI", "icon": Icons.qr_code_rounded},
    {"label": "Card", "icon": Icons.credit_card_rounded},
  ];

  Widget _buildPaymentRow() {
    final selectedIcon = (_paymentOptions.firstWhere((o) => o["label"] == selectedPaymentMethod, orElse: () => _paymentOptions.first)["icon"] as IconData);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Payment", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showPaymentPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFF4A261).withOpacity(0.4))),
              child: Row(
                children: [
                  Icon(selectedIcon, size: 18, color: const Color(0xFFF4A261)),
                  const SizedBox(width: 10),
                  Text(selectedPaymentMethod, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  const Spacer(),
                  Icon(Icons.expand_more_rounded, size: 20, color: Colors.white.withOpacity(0.45)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(color: const Color(0xFF1A1C1C), borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), border: Border.all(color: Colors.white.withOpacity(0.09))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(2)))),
            const Text("Select Payment Method", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ..._paymentOptions.map((option) {
              final label = option["label"] as String;
              final isSelected = selectedPaymentMethod == label;
              return GestureDetector(
                onTap: () { setState(() => selectedPaymentMethod = label); Navigator.pop(ctx); },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(color: isSelected ? const Color(0xFFF4A261).withOpacity(0.12) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: isSelected ? const Color(0xFFF4A261).withOpacity(0.5) : Colors.white.withOpacity(0.08))),
                  child: Row(
                    children: [
                      Icon(option["icon"] as IconData, size: 20, color: isSelected ? const Color(0xFFF4A261) : Colors.white.withOpacity(0.6)),
                      const SizedBox(width: 14),
                      Text(label, style: TextStyle(color: isSelected ? const Color(0xFFF4A261) : Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      if (isSelected) ...[const Spacer(), const Icon(Icons.check_circle_rounded, color: Color(0xFFF4A261), size: 20)],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBookButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: ElevatedButton.icon(
        onPressed: canSubmit ? _requestRide : null,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          backgroundColor: const Color(0xFFF4A261),
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFFF4A261).withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        icon: isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.bike_scooter_rounded, size: 20),
        label: Text(isLoading ? "Searching riders…" : "Book Ride", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildSuggestedFareRow() {
    final fare = estimatedFare;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF4A261).withOpacity(0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF4A261).withOpacity(0.22))),
        child: Row(
          children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFF4A261).withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.currency_rupee_rounded, color: Color(0xFFF4A261), size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Suggested Fare", style: TextStyle(fontSize: 11, color: Color(0xFFF4A261), fontWeight: FontWeight.w700)),
                  Text(fare != null ? "₹ ${fare.round().toStringAsFixed(2)}" : "--", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                ],
              ),
            ),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFF4A261).withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: const Text("Negotiable", style: TextStyle(fontSize: 10, color: Color(0xFFF4A261), fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
  }

  Widget _buildNegotiationInfoCard() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.08))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: const Color(0xFFF4A261).withOpacity(0.12), borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.handshake_rounded, color: Color(0xFFF4A261), size: 16)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("How Negotiation Works", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)), SizedBox(height: 4), Text("Propose a counter-fare strategy. Nearby dynamic riders evaluate parameters to accept or adjust offers.", style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4))])),
          ],
        ),
      ),
    );
  }

  Widget _buildNegotiateFareButton() {
    final enabled = canSubmit && !isLoading;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: ElevatedButton.icon(
        onPressed: enabled ? _showNegotiationModal : null,
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          backgroundColor: const Color(0xFFF4A261),
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFFF4A261).withOpacity(0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        icon: const Icon(Icons.handshake_rounded, size: 19),
        label: const Text("Start Negotiation", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ),
    );
  }

  void _showNegotiationModal() {
    _fitMapToRoute(force: true);
    final suggested = estimatedFare ?? 0.0;
    double offerAmount = double.tryParse(_offerController.text.trim()) ?? (suggested * 0.85);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void adjust(double delta) => setModalState(() => offerAmount = (offerAmount + delta).clamp(1, suggested * 2));
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF141616), borderRadius: const BorderRadius.vertical(top: Radius.circular(28)), border: Border.all(color: Colors.white.withOpacity(0.09))),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 18), decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(2)))),
                  const Text("Negotiate Fare", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text("Suggested Baseline: ₹ ${suggested.round().toStringAsFixed(2)}", style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13)),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(color: const Color(0xFFF4A261).withOpacity(0.07), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFF4A261).withOpacity(0.22))),
                    child: Column(
                      children: [
                        Text("Counter Proposal Offer", style: TextStyle(color: const Color(0xFFF4A261).withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w700)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("₹", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 4),
                            Text(offerAmount.round().toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [Expanded(child: _modalAdjustButton("− ₹10", () => adjust(-10))), const SizedBox(width: 8), Expanded(child: _modalAdjustButton("− ₹20", () => adjust(-20))), const SizedBox(width: 8), Expanded(child: _modalAdjustButton("− ₹30", () => adjust(-30)))]),
                  const SizedBox(height: 8),
                  Row(children: [Expanded(child: _modalAdjustButton("+ ₹10", () => adjust(10), positive: true)), const SizedBox(width: 8), Expanded(child: _modalAdjustButton("+ ₹20", () => adjust(20), positive: true)), const SizedBox(width: 8), Expanded(child: _modalAdjustButton("+ ₹30", () => adjust(30), positive: true))]),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: isLoading ? null : () {
                      _offerController.text = offerAmount.toStringAsFixed(0);
                      Navigator.pop(ctx);
                      _requestRide();
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56), backgroundColor: const Color(0xFFF4A261), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                    child: Text("Transmit Offer Request · ₹ ${offerAmount.round().toStringAsFixed(2)}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _modalAdjustButton(String label, VoidCallback onTap, {bool positive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: positive ? const Color(0xFF16A34A).withOpacity(0.10) : const Color(0xFFDC2626).withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: positive ? const Color(0xFF16A34A).withOpacity(0.22) : const Color(0xFFDC2626).withOpacity(0.22)),
        ),
        child: Center(child: Text(label, style: TextStyle(color: positive ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5), fontWeight: FontWeight.w800, fontSize: 13))),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io_client;
import '../config/app_config.dart';
import 'api_service.dart';
import 'session_service.dart';

class SocketService {
  static io_client.Socket? _socket;

  static io_client.Socket get socket {
    if (_socket == null) {
      connect();
    }
    return _socket!;
  }

  static bool get isConnected => _socket != null && _socket!.connected;

  static void connect({String? token, String? userId, String? sessionId}) {
    final session = SessionService.loadSession();
    final effectiveToken = token ?? session?['token'];
    final effectiveUserId = userId ?? session?['userId'];
    final effectiveSessionId = sessionId ?? session?['sessionId'];

    final apiBase = AppConfig.apiBaseUrl;
    final socketUrl = apiBase.endsWith("/api")
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;

    final authMap = <String, dynamic>{};
    if (effectiveToken != null && effectiveToken.isNotEmpty) {
      authMap['token'] = effectiveToken;
    }
    if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
      authMap['userId'] = effectiveUserId;
    }
    if (effectiveSessionId != null && effectiveSessionId.isNotEmpty) {
      authMap['sessionId'] = effectiveSessionId;
    }

    if (_socket != null) {
      if (!_socket!.connected) {
        _socket!.connect();
      }
      if (effectiveUserId != null && effectiveUserId.isNotEmpty) {
        authenticate(
          token: effectiveToken,
          userId: effectiveUserId,
          sessionId: effectiveSessionId,
        );
      }
      return;
    }

    final builder = io_client.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect();

    if (authMap.isNotEmpty) {
      builder.setAuth(authMap);
      builder.setQuery(authMap);
    }

    _socket = io_client.io(
      socketUrl,
      builder.build(),
    );

    _socket!.onConnect((_) {
      if (kDebugMode) {
        print("[SOCKET] Connected: ${_socket!.id}");
      }
      final currentSession = SessionService.loadSession();
      if (currentSession != null &&
          currentSession['userId'] != null &&
          currentSession['userId']!.isNotEmpty) {
        authenticate(
          token: currentSession['token'],
          userId: currentSession['userId'],
          sessionId: currentSession['sessionId'],
        );
      }
    });

    _socket!.onDisconnect((_) {
      if (kDebugMode) {
        print("[SOCKET] Disconnected");
      }
    });

    _setupGlobalSecurityListeners(_socket!);

    try {
      _socket!.connect();
    } catch (e) {
      if (kDebugMode) {
        print("[SOCKET] Connect error: $e");
      }
    }
  }

  static void _setupGlobalSecurityListeners(io_client.Socket s) {
    s.on("force_logout", (data) {
      _handleSessionReplaced(data);
    });

    s.on("session_replaced", (data) {
      _handleSessionReplaced(data);
    });
  }

  static void _handleSessionReplaced(dynamic data) {
    if (kDebugMode) {
      print("[SOCKET] force_logout received: $data");
    }

    final currentSession = SessionService.loadSession();
    if (currentSession == null) {
      return; // Already logged out
    }

    final currentSessionId = currentSession['sessionId'];
    if (data is Map &&
        data['newSessionId'] != null &&
        currentSessionId != null &&
        currentSessionId.isNotEmpty) {
      if (data['newSessionId'].toString() == currentSessionId) {
        if (kDebugMode) {
          print("[SOCKET] Ignoring kick event for current active session");
        }
        return;
      }
    }

    String message = "Logged out: Your account was signed in on another device";
    if (data is Map && data['message'] != null) {
      message = data['message'].toString();
    }

    ApiService.triggerAutoLogout(message: message);
  }

  static void authenticate({String? token, String? userId, String? sessionId}) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("authenticate", {
        "token": token,
        "userId": userId,
        "sessionId": sessionId,
      });
      if (userId != null && userId.isNotEmpty) {
        _socket!.emit("join_user_room", {
          "userId": userId,
          "sessionId": sessionId,
        });
      }
    }
  }

  static void disconnect() {
    try {
      _socket?.disconnect();
    } catch (_) {}
  }

  static void listenRideAccepted(Function callback) {
    socket.on("rideAccepted", (data) {
      callback(data);
    });
  }

  static void listenRideRequested(Function callback) {
    socket.on("rideRequested", (data) {
      callback(data);
    });
  }

  static void listenRideStarted(Function callback) {
    socket.on("rideStarted", (data) {
      callback(data);
    });
  }

  static void listenRideCompleted(Function callback) {
    socket.on("rideCompleted", (data) {
      callback(data);
    });
  }

  static void listenRideCancelled(Function callback) {
    socket.on("rideCancelled", (data) {
      callback(data);
    });
  }

  static void listenNegotiationRideRequested(Function callback) {
    socket.on("negotiationRideRequested", (data) {
      callback(data);
    });
  }

  static void listenNegotiationOfferSubmitted(Function callback) {
    socket.on("negotiationOfferSubmitted", (data) {
      callback(data);
    });
  }

  static void listenNegotiationOfferAcceptedByUser(Function callback) {
    socket.on("negotiationOfferAcceptedByUser", (data) {
      callback(data);
    });
  }

  static void listenNegotiationClosed(Function callback) {
    socket.on("negotiationClosed", (data) {
      callback(data);
    });
  }

  static void listenNegotiationExpired(Function callback) {
    socket.on("negotiationExpired", (data) {
      callback(data);
    });
  }

  static void emitDriverOnline(String driverId, double lat, double lng) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("driver_online", {
        "driverId": driverId,
        "lat": lat,
        "lng": lng,
        "location": {"lat": lat, "lng": lng},
      });
    }
  }

  static void emitDriverOffline(String driverId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("driver_offline", {
        "driverId": driverId,
      });
    }
  }

  static void emitDriverLocationUpdate(String driverId, double lat, double lng) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("driver_location_update", {
        "driverId": driverId,
        "lat": lat,
        "lng": lng,
        "location": {"lat": lat, "lng": lng},
      });
    }
  }

  static void emitJoinRide(String rideId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("join_ride", {"rideId": rideId});
    }
  }

  static void emitUpdateRiderLocation(String rideId, double lat, double lng) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("update_rider_location", {
        "rideId": rideId,
        "lat": lat,
        "lng": lng,
      });
    }
  }

  static void emitUpdateDriverLocation(String rideId, String driverId, double lat, double lng) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit("update_driver_location", {
        "rideId": rideId,
        "driverId": driverId,
        "lat": lat,
        "lng": lng,
      });
    }
  }

  static void listenRiderLocationUpdated(Function callback) {
    socket.on("rider_location_updated", (data) {
      callback(data);
    });
  }

  static void stopListeningRiderLocationUpdated() {
    socket.off("rider_location_updated");
  }

  static void listenDriverAvailabilityChanged(Function callback) {
    socket.on("driver_availability_changed", (data) {
      callback(data);
    });
  }

  static void stopListeningDriverAvailabilityChanged() {
    socket.off("driver_availability_changed");
  }

  static void listenDriverStatusChanged(Function callback) {
    socket.on("driver_status_changed", (data) {
      callback(data);
    });
  }

  static void stopListeningDriverStatusChanged() {
    socket.off("driver_status_changed");
  }

  static void listenDriverLocationUpdated(Function callback) {
    socket.on("driverLocationUpdated", (data) {
      callback(data);
    });
  }

  static void stopListeningDriverLocationUpdated() {
    socket.off("driverLocationUpdated");
  }

  static void removeAllRideListeners() {
    socket.off("rideRequested");
    socket.off("rideAccepted");
    socket.off("rideStarted");
    socket.off("rideCompleted");
    socket.off("rideCancelled");
    socket.off("negotiationRideRequested");
    socket.off("negotiationOfferSubmitted");
    socket.off("negotiationOfferAcceptedByUser");
    socket.off("negotiationClosed");
    socket.off("negotiationExpired");
  }
}

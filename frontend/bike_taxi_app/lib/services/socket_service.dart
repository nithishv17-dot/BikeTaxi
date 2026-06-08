import 'package:socket_io_client/socket_io_client.dart' as io_client;
import '../config/app_config.dart';

class SocketService {
  static late io_client.Socket socket;

  static void connect() {
    final apiBase = AppConfig.apiBaseUrl;
    final socketUrl = apiBase.endsWith("/api")
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;

    socket = io_client.io(
      socketUrl,
      io_client.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();
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

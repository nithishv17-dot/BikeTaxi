import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {

  static late IO.Socket socket;

  static void connect() {

    socket = IO.io(
      "http://10.0.2.2:5000",
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .build(),
    );

    socket.connect();

  }

  static void requestRide(Map<String, dynamic> rideData) {
    socket.emit("requestRide", rideData);
  }

  static void listenRideAccepted(Function callback) {
    socket.on("rideAccepted", (data) {
      callback(data);
    });
  }

}
import { io, Socket } from "socket.io-client";

export interface DriverLocationUpdate {
  driverId: string;
  lat: number;
  lng: number;
  heading?: number;
}

export class SocketService {
  private static socket: Socket | null = null;
  private static serverUrl = "http://localhost:5000";

  static init(url = "http://localhost:5000"): Socket {
    if (!this.socket) {
      this.serverUrl = url;
      this.socket = io(this.serverUrl, {
        transports: ["websocket", "polling"],
        reconnection: true,
        reconnectionAttempts: 5,
        reconnectionDelay: 1000,
      });

      this.socket.on("connect", () => {
        console.log("Socket connected to RideGo backend:", this.socket?.id);
      });

      this.socket.on("disconnect", (reason) => {
        console.log("Socket disconnected:", reason);
      });
    }

    return this.socket;
  }

  static getSocket(): Socket | null {
    return this.socket;
  }

  static onDriverLocationUpdated(callback: (data: DriverLocationUpdate) => void) {
    const s = this.socket || this.init();
    s.on("driverLocationUpdated", callback);
  }

  static offDriverLocationUpdated(callback?: (data: DriverLocationUpdate) => void) {
    if (this.socket) {
      if (callback) {
        this.socket.off("driverLocationUpdated", callback);
      } else {
        this.socket.off("driverLocationUpdated");
      }
    }
  }

  static emitDriverLocation(driverId: string, lat: number, lng: number) {
    const s = this.socket || this.init();
    s.emit("updateDriverLocation", { driverId, lat, lng });
  }

  static disconnect() {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
  }
}

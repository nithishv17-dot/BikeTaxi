const express = require("express");
const mongoose = require("mongoose");
const http = require("http");
const { Server } = require("socket.io");
const ridesRoutes = require("./routes/rideRoutes");
const userRoutes = require("./routes/userRoutes");
const driverRoutes = require("./routes/driverRoutes");
const cors = require("cors");

const app = express();

app.use("/api/drivers", driverRoutes);


app.use(cors({
  origin: true, // ⚠️ your flutter port (check it)
  credentials: true
}));
app.use(express.json());

/* ---------------- DATABASE ---------------- */

mongoose.connect("mongodb://127.0.0.1:27017/biketaxi")
.then(()=>{
    console.log("MongoDB Connected");
})
.catch((err)=>{
    console.log(err);
});

/* ---------------- ROUTES ---------------- */

app.use("/api/users",userRoutes);
app.use("/api/rides", ridesRoutes);
app.use("/api/drivers",driverRoutes);

/* ---------------- SOCKET SERVER ---------------- */

const server = http.createServer(app);

const io = new Server(server, {
  cors: {
    origin: "*"
  }
});

app.use(express.json());

io.on("connection", (socket) => {
  console.log("User connected:", socket.id);

  socket.on("requestRide", (data) => {
    console.log("Ride requested:", data);

    // broadcast to drivers
    io.emit("newRideRequest", data);
  });

  socket.on("acceptRide", (data) => {
    console.log("Ride accepted:", data);

    // send update to user
    io.emit("rideAccepted", data);
  });

});

/* ---------------- START SERVER ---------------- */

const PORT = 5000;

server.listen(PORT,()=>{
    console.log(`Server running on port ${PORT}`);
});
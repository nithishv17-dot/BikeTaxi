const express = require("express");
const mongoose = require("mongoose");
const http = require("http");
const { Server } = require("socket.io");
require("dotenv").config();
const rideController = require("./controllers/rideController");
const ridesRoutes = require("./routes/rideRoutes");
const userRoutes = require("./routes/userRoutes");
const driverRoutes = require("./routes/driverRoutes");
const cors = require("cors");

const app = express();

app.use(cors({
  origin: true,
  credentials: true
}));
app.use(express.json());

/* ---------------- DATABASE ---------------- */

mongoose.connect(process.env.MONGODB_URI || "mongodb://127.0.0.1:27017/biketaxi")
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

app.set("io", io);

app.use(express.json());

io.on("connection", (socket) => {
  console.log("User connected:", socket.id);
});

setInterval(async () => {
  try {
    await rideController.expireOpenNegotiations(io);
  } catch (error) {
    console.log("NEGOTIATION SWEEP ERROR:", error.message);
  }
}, 10000);

/* ---------------- START SERVER ---------------- */

const PORT = process.env.PORT || 5000;

server.listen(PORT,()=>{
    console.log(`Server running on port ${PORT}`);
});

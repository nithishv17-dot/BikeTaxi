const jwt = require("jsonwebtoken");
const User = require("../models/User");

module.exports = async function(req, res, next) {
  const authHeader = req.header("Authorization");

  if (!authHeader) {
    return res.status(401).json({
      success: false,
      code: "NO_TOKEN",
      message: "No token provided"
    });
  }

  const token = authHeader.startsWith("Bearer ")
    ? authHeader.split(" ")[1]
    : authHeader;

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET || "secretkey");

    // Fetch user and check active session ID from MongoDB
    const user = await User.findById(decoded.id);
    if (!user || !user.activeSessionId || decoded.sessionId !== user.activeSessionId) {
      return res.status(401).json({
        success: false,
        code: "SESSION_REPLACED",
        message: "Session expired because your account was logged in on another device."
      });
    }

    req.user = decoded;
    req.userDoc = user;
    next();
  } catch (err) {
    return res.status(401).json({
      success: false,
      code: "INVALID_TOKEN",
      message: "Invalid or expired token"
    });
  }
};

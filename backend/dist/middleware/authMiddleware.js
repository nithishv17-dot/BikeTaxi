"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateToken = exports.authMiddleware = void 0;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const errorHandler_1 = require("./errorHandler");
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';
const authMiddleware = (req, res, next) => {
    const token = req.headers.authorization?.split(' ')[1];
    if (!token) {
        throw new errorHandler_1.ApiError(401, 'No token provided');
    }
    try {
        const decoded = jsonwebtoken_1.default.verify(token, JWT_SECRET);
        req.userId = decoded.userId;
        next();
    }
    catch (error) {
        throw new errorHandler_1.ApiError(401, 'Invalid token');
    }
};
exports.authMiddleware = authMiddleware;
const generateToken = (userId, role) => {
    return jsonwebtoken_1.default.sign({ userId, role }, JWT_SECRET, { expiresIn: '24h' });
};
exports.generateToken = generateToken;
//# sourceMappingURL=authMiddleware.js.map
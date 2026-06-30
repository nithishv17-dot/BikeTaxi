"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApp = void 0;
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const logger_1 = require("./utils/logger");
const errorHandler_1 = require("./middleware/errorHandler");
const users_1 = __importDefault(require("./routes/users"));
const rides_1 = __importDefault(require("./routes/rides"));
const drivers_1 = __importDefault(require("./routes/drivers"));
const logger = (0, logger_1.createLogger)('app');
const createApp = () => {
    const app = (0, express_1.default)();
    // Middleware
    app.use((0, cors_1.default)());
    app.use(express_1.default.json());
    app.use(express_1.default.urlencoded({ extended: true }));
    // Request logging middleware
    app.use((req, res, next) => {
        logger.info({
            method: req.method,
            path: req.path,
            ip: req.ip,
        });
        next();
    });
    // Health check endpoint
    app.get('/health', (req, res) => {
        res.json({ status: 'ok', timestamp: new Date().toISOString() });
    });
    // API Routes
    app.use('/api/users', users_1.default);
    app.use('/api/rides', rides_1.default);
    app.use('/api/drivers', drivers_1.default);
    // 404 handler
    app.use((req, res) => {
        res.status(404).json({ error: 'Route not found' });
    });
    // Error handler (must be last)
    app.use(errorHandler_1.errorHandler);
    return app;
};
exports.createApp = createApp;
//# sourceMappingURL=app.js.map
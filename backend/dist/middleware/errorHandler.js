"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.errorHandler = exports.ApiError = void 0;
const zod_1 = require("zod");
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.createLogger)('errorHandler');
class ApiError extends Error {
    constructor(statusCode, message) {
        super(message);
        this.statusCode = statusCode;
        this.name = 'ApiError';
    }
}
exports.ApiError = ApiError;
const errorHandler = (err, req, res, next) => {
    logger.error({ error: err }, 'Unhandled error');
    if (err instanceof ApiError) {
        return res.status(err.statusCode).json({ error: err.message });
    }
    if (err instanceof zod_1.ZodError) {
        return res.status(400).json({
            error: 'Validation error',
            details: err.errors,
        });
    }
    // Default error
    res.status(500).json({
        error: 'Internal server error',
    });
};
exports.errorHandler = errorHandler;
//# sourceMappingURL=errorHandler.js.map
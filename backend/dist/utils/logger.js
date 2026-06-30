"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createLogger = void 0;
const pino_1 = __importDefault(require("pino"));
const isDevelopment = process.env.NODE_ENV !== 'production';
const createLogger = (name) => {
    return (0, pino_1.default)({
        name,
        level: isDevelopment ? 'debug' : 'info',
    }, isDevelopment
        ? pino_1.default.transport({
            target: 'pino-pretty',
            options: {
                colorize: true,
                singleLine: false,
                translateTime: 'HH:MM:ss Z',
            },
        })
        : undefined);
};
exports.createLogger = createLogger;
//# sourceMappingURL=logger.js.map
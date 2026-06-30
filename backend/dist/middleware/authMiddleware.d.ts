import { Response, NextFunction } from 'express';
import { AuthRequest } from '../types';
export interface JwtPayload {
    userId: string;
    role: string;
}
export declare const authMiddleware: (req: AuthRequest, res: Response, next: NextFunction) => void;
export declare const generateToken: (userId: string, role: string) => string;
//# sourceMappingURL=authMiddleware.d.ts.map
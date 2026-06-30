import { DualWriteManager } from '../middleware/dualWrite';
import { PrismaClient } from '@prisma/client';

// Mock implementations
const mockPrisma = {
  user: {
    create: jest.fn(),
    update: jest.fn(),
  },
  ride: {
    create: jest.fn(),
    update: jest.fn(),
  },
};

const mockMongoModel = {
  save: jest.fn(),
  findByIdAndUpdate: jest.fn(),
};

describe('DualWriteManager', () => {
  let dualWriteManager: DualWriteManager;

  beforeEach(() => {
    dualWriteManager = new DualWriteManager(mockPrisma as any);
    jest.clearAllMocks();
  });

  describe('writeUser', () => {
    it('should write user to both databases', async () => {
      const userData = {
        _id: 'user123',
        name: 'Test User',
        phone: '9876543210',
        password: 'hashed_password',
        role: 'USER',
      };

      mockMongoModel.save.mockResolvedValue(userData);
      mockPrisma.user.create.mockResolvedValue({
        id: 'user123',
        name: 'Test User',
      });

      // In lenient mode, should not throw
      dualWriteManager.setEnabled(true);
      const result = await dualWriteManager.writeUser(mockMongoModel, userData, 'create');

      expect(result.mongo).toBeDefined();
      expect(result.postgres).toBeDefined();
    });

    it('should handle PostgreSQL write failure in lenient mode', async () => {
      const userData = {
        _id: 'user123',
        name: 'Test User',
        phone: '9876543210',
        password: 'hashed_password',
      };

      mockMongoModel.save.mockResolvedValue(userData);
      mockPrisma.user.create.mockRejectedValue(new Error('DB Error'));

      dualWriteManager.setEnabled(true);
      const result = await dualWriteManager.writeUser(mockMongoModel, userData, 'create');

      // Should still succeed with lenient mode
      expect(result.mongo).toBeDefined();
    });
  });

  describe('getMigrationStats', () => {
    it('should return migration statistics', async () => {
      dualWriteManager.setEnabled(true);

      const stats = dualWriteManager.getMigrationStats();

      expect(stats).toHaveProperty('totalOperations');
      expect(stats).toHaveProperty('successfulDualWrites');
      expect(stats).toHaveProperty('mongoFailures');
      expect(stats).toHaveProperty('postgresFailures');
      expect(stats).toHaveProperty('successRate');
      expect(stats).toHaveProperty('dualWriteEnabled');
    });
  });

  describe('enable/disable', () => {
    it('should enable and disable dual-write', () => {
      dualWriteManager.setEnabled(true);
      let stats = dualWriteManager.getMigrationStats();
      expect(stats.dualWriteEnabled).toBe(true);

      dualWriteManager.setEnabled(false);
      stats = dualWriteManager.getMigrationStats();
      expect(stats.dualWriteEnabled).toBe(false);
    });
  });

  describe('write log', () => {
    it('should clear write log', () => {
      dualWriteManager.clearLog();
      const log = dualWriteManager.getWriteLog();
      expect(log.length).toBe(0);
    });
  });
});

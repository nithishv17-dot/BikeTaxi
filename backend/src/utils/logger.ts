import pino from 'pino';

const isDevelopment = process.env.NODE_ENV !== 'production';

export const createLogger = (name: string) => {
  return pino(
    {
      name,
      level: isDevelopment ? 'debug' : 'info',
    },
    isDevelopment
      ? pino.transport({
          target: 'pino-pretty',
          options: {
            colorize: true,
            singleLine: false,
            translateTime: 'HH:MM:ss Z',
          },
        })
      : undefined
  );
};

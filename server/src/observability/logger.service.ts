import { Injectable, LoggerService } from '@nestjs/common';

type LogPayload = {
  level: string;
  message: string;
  timestamp: string;
  context?: string;
  meta?: Record<string, unknown>;
};

@Injectable()
export class JsonLogger implements LoggerService {
  log(message: unknown, ...optionalParams: unknown[]): void {
    this.write('info', message, optionalParams);
  }

  error(message: unknown, ...optionalParams: unknown[]): void {
    this.write('error', message, optionalParams);
  }

  warn(message: unknown, ...optionalParams: unknown[]): void {
    this.write('warn', message, optionalParams);
  }

  debug(message: unknown, ...optionalParams: unknown[]): void {
    this.write('debug', message, optionalParams);
  }

  verbose(message: unknown, ...optionalParams: unknown[]): void {
    this.write('verbose', message, optionalParams);
  }

  private write(level: string, message: unknown, optionalParams: unknown[]): void {
    const timestamp = new Date().toISOString();
    const [context, meta] = this.normalizeParams(optionalParams);
    const payload: LogPayload = {
      level,
      message: this.formatMessage(message),
      timestamp,
    };
    if (context) {
      payload.context = context;
    }
    if (meta) {
      payload.meta = meta;
    }
    if (level === 'error') {
      console.error(JSON.stringify(payload));
      return;
    }
    console.log(JSON.stringify(payload));
  }

  private normalizeParams(optionalParams: unknown[]): [string | undefined, Record<string, unknown> | undefined] {
    if (optionalParams.length === 0) {
      return [undefined, undefined];
    }
    const maybeContext = optionalParams[0];
    const maybeMeta = optionalParams.length > 1 ? optionalParams[1] : undefined;

    const context = typeof maybeContext === 'string' ? maybeContext : undefined;
    const meta =
      this.isRecord(maybeMeta) ? maybeMeta : this.isRecord(maybeContext) ? maybeContext : undefined;

    return [context, meta];
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
  }

  private formatMessage(message: unknown): string {
    if (message instanceof Error) {
      return message.message;
    }
    if (typeof message === 'string') {
      return message;
    }
    try {
      return JSON.stringify(message);
    } catch {
      return String(message);
    }
  }
}

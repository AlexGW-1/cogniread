import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable, catchError, throwError, tap } from 'rxjs';
import { JsonLogger } from './logger.service';
import { MetricsService } from './metrics.service';
import { Request, Response } from 'express';
import { getTraceContext } from './trace.util';

@Injectable()
export class LoggingInterceptor implements NestInterceptor {
  constructor(
    private readonly logger: JsonLogger,
    private readonly metrics: MetricsService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const http = context.switchToHttp();
    const req = http.getRequest<Request & { requestId?: string; userId?: string }>();
    const res = http.getResponse<Response>();
    const start = Date.now();

    return next.handle().pipe(
      tap(() => {
        const durationMs = Date.now() - start;
        const status = res.statusCode ?? 200;
        const route = req.route?.path
          ? `${req.baseUrl ?? ''}${req.route.path}`
          : req.path ?? req.url ?? 'unknown';
        const traceContext = getTraceContext();
        this.metrics.observeHttp(req.method, route, status, durationMs);
        this.logger.log('http_request', {
          method: req.method,
          path: route,
          status,
          durationMs,
          requestId: req.requestId,
          userId: req.userId,
          ...traceContext,
        });
      }),
      catchError((error) => {
        const durationMs = Date.now() - start;
        const status = res.statusCode ?? 500;
        const route = req.route?.path
          ? `${req.baseUrl ?? ''}${req.route.path}`
          : req.path ?? req.url ?? 'unknown';
        const traceContext = getTraceContext();
        this.metrics.observeHttp(req.method, route, status, durationMs);
        this.logger.error('http_error', {
          method: req.method,
          path: route,
          status,
          durationMs,
          requestId: req.requestId,
          userId: req.userId,
          error: error?.message ?? String(error),
          ...traceContext,
        });
        return throwError(() => error);
      }),
    );
  }
}

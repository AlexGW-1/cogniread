import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { HttpAdapterHost } from '@nestjs/core';
import { IncomingMessage } from 'node:http';
import { WebSocketServer, WebSocket } from 'ws';
import type { RawData } from 'ws';
import { SyncService } from './sync.service';
import { SyncEventsBus, EventsAvailablePayload } from './sync.events';
import { extractUserIdFromAuthHeader } from './auth.util';
import { MetricsService } from '../observability/metrics.service';
import { JsonLogger } from '../observability/logger.service';
import { getTraceContext } from '../observability/trace.util';
import { SpanStatusCode, trace } from '@opentelemetry/api';

type ClientState = {
  userId: string;
  deviceId?: string;
  lastSeenCursor?: string | null;
};

type HelloMessage = {
  type: 'hello';
  deviceId: string;
  lastSeenCursor?: string | null;
};

type PullMessage = {
  type: 'pull';
  cursor?: string | null;
};

const MAX_LIMIT = 200;

const decodeRaw = (raw: RawData): string => {
  if (typeof raw === 'string') {
    return raw;
  }
  if (raw instanceof Buffer) {
    return raw.toString('utf8');
  }
  if (raw instanceof ArrayBuffer) {
    return Buffer.from(new Uint8Array(raw)).toString('utf8');
  }
  if (Array.isArray(raw)) {
    return Buffer.concat(raw).toString('utf8');
  }
  if (raw instanceof Uint8Array) {
    return Buffer.from(raw).toString('utf8');
  }
  return '';
};

@Injectable()
export class SyncWsGateway implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(SyncWsGateway.name);
  private wss?: WebSocketServer;
  private unsubscribe?: () => void;
  private readonly clientsByUser = new Map<string, Set<WebSocket>>();
  private readonly stateBySocket = new WeakMap<WebSocket, ClientState>();

  constructor(
    private readonly adapterHost: HttpAdapterHost,
    private readonly syncService: SyncService,
    private readonly eventsBus: SyncEventsBus,
    private readonly metrics: MetricsService,
    private readonly logger: JsonLogger,
  ) {}

  onModuleInit(): void {
    const httpServer = this.adapterHost.httpAdapter.getHttpServer();
    this.wss = new WebSocketServer({ server: httpServer, path: '/sync/ws' });
    this.wss.on('connection', (socket, request) =>
      this.handleConnection(socket, request),
    );
    this.unsubscribe = this.eventsBus.onEventsAvailable((payload) =>
      this.broadcastEventsAvailable(payload),
    );
    this.logger.log('Sync WS server initialized on /sync/ws');
  }

  onModuleDestroy(): void {
    this.unsubscribe?.();
    this.wss?.close();
  }

  private handleConnection(socket: WebSocket, request: IncomingMessage): void {
    const userId = extractUserIdFromAuthHeader(request.headers.authorization);
    if (!userId) {
      socket.close(1008, 'Unauthorized');
      return;
    }

    const clients = this.clientsByUser.get(userId) ?? new Set<WebSocket>();
    clients.add(socket);
    this.clientsByUser.set(userId, clients);
    this.stateBySocket.set(socket, { userId });
    this.metrics.recordWsConnected();

    socket.on('message', (raw) => void this.handleMessage(socket, raw));
    socket.on('close', () => {
      this.metrics.recordWsDisconnected();
      clients.delete(socket);
      if (clients.size === 0) {
        this.clientsByUser.delete(userId);
      }
    });
  }

  private async handleMessage(socket: WebSocket, raw: RawData): Promise<void> {
    let message: unknown;
    try {
      message = JSON.parse(decodeRaw(raw));
    } catch {
      this.safeSend(socket, { type: 'error', reason: 'invalid_json' });
      return;
    }

    if (!message || typeof message !== 'object' || !('type' in message)) {
      this.safeSend(socket, { type: 'error', reason: 'invalid_message' });
      return;
    }

    const state = this.stateBySocket.get(socket);
    if (!state) {
      this.safeSend(socket, { type: 'error', reason: 'unauthorized' });
      return;
    }

    if ((message as HelloMessage).type === 'hello') {
      const hello = message as HelloMessage;
      if (typeof hello.deviceId !== 'string' || hello.deviceId.length === 0) {
        this.safeSend(socket, { type: 'error', reason: 'invalid_device_id' });
        return;
      }
      const tracer = trace.getTracer('sync-ws');
      tracer.startActiveSpan('sync.ws.hello', (span) => {
        state.deviceId = hello.deviceId;
        state.lastSeenCursor = hello.lastSeenCursor ?? null;
        this.logger.log('sync.ws.hello', {
          userId: state.userId,
          deviceId: hello.deviceId,
          lastSeenCursor: hello.lastSeenCursor ?? null,
          ...getTraceContext(),
        });
        span.end();
      });
      return;
    }

    if ((message as PullMessage).type === 'pull') {
      const pull = message as PullMessage;
      const tracer = trace.getTracer('sync-ws');
      await tracer.startActiveSpan('sync.ws.pull', async (span) => {
        try {
          const { events, serverCursor } = await this.syncService.listEvents(
            state.userId,
            pull.cursor,
            MAX_LIMIT,
          );
          this.logger.log('sync.ws.pull', {
            userId: state.userId,
            cursor: pull.cursor ?? null,
            limit: MAX_LIMIT,
            returned: events.length,
            ...getTraceContext(),
          });
          this.safeSend(socket, {
            type: 'events',
            events,
            serverCursor,
          });
        } catch (error) {
          span.recordException(error as Error);
          span.setStatus({ code: SpanStatusCode.ERROR });
          this.safeSend(socket, { type: 'error', reason: 'invalid_cursor' });
        } finally {
          span.end();
        }
      });
      return;
    }

    this.safeSend(socket, { type: 'error', reason: 'unknown_type' });
  }

  private broadcastEventsAvailable(payload: EventsAvailablePayload): void {
    if (!payload.serverCursor) {
      return;
    }
    const sockets = this.clientsByUser.get(payload.userId);
    if (!sockets || sockets.size === 0) {
      return;
    }
    const tracer = trace.getTracer('sync-ws');
    tracer.startActiveSpan('sync.ws.events_available', (span) => {
      this.logger.log('sync.ws.events_available', {
        userId: payload.userId,
        serverCursor: payload.serverCursor,
        recipients: sockets.size,
        ...getTraceContext(),
      });
      span.end();
    });
    for (const socket of sockets) {
      this.safeSend(socket, {
        type: 'events_available',
        serverCursor: payload.serverCursor,
      });
    }
  }

  private safeSend(socket: WebSocket, payload: Record<string, unknown>): void {
    if (socket.readyState !== WebSocket.OPEN) {
      return;
    }
    socket.send(JSON.stringify(payload));
  }
}

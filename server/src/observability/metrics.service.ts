import { Injectable } from '@nestjs/common';
import client, { Counter, Histogram, Registry } from 'prom-client';

@Injectable()
export class MetricsService {
  private readonly registry = new Registry();
  private readonly httpRequestsTotal: Counter<'method' | 'route' | 'status'>;
  private readonly httpRequestDurationMs: Histogram<'method' | 'route' | 'status'>;
  private readonly syncEventsAccepted: Counter;
  private readonly syncEventsDuplicate: Counter;
  private readonly syncEventsRejected: Counter;
  private readonly syncEventsPulled: Counter;
  private readonly syncStateUpdates: Counter;
  private readonly syncWsConnected: Counter;
  private readonly syncWsDisconnects: Counter;

  constructor() {
    client.collectDefaultMetrics({ register: this.registry });

    this.httpRequestsTotal = new client.Counter({
      name: 'http_requests_total',
      help: 'Total HTTP requests',
      labelNames: ['method', 'route', 'status'],
      registers: [this.registry],
    });

    this.httpRequestDurationMs = new client.Histogram({
      name: 'http_request_duration_ms',
      help: 'HTTP request duration in ms',
      labelNames: ['method', 'route', 'status'],
      buckets: [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000],
      registers: [this.registry],
    });

    this.syncEventsAccepted = new client.Counter({
      name: 'sync_events_accepted_total',
      help: 'Accepted sync events',
      registers: [this.registry],
    });

    this.syncEventsDuplicate = new client.Counter({
      name: 'sync_events_duplicate_total',
      help: 'Duplicate sync events',
      registers: [this.registry],
    });

    this.syncEventsRejected = new client.Counter({
      name: 'sync_events_rejected_total',
      help: 'Rejected sync events',
      registers: [this.registry],
    });

    this.syncEventsPulled = new client.Counter({
      name: 'sync_events_pulled_total',
      help: 'Events returned by pull API',
      registers: [this.registry],
    });

    this.syncStateUpdates = new client.Counter({
      name: 'sync_state_updates_total',
      help: 'Sync state updates (reading positions)',
      registers: [this.registry],
    });

    this.syncWsConnected = new client.Counter({
      name: 'sync_ws_connected_total',
      help: 'WS connections established',
      registers: [this.registry],
    });

    this.syncWsDisconnects = new client.Counter({
      name: 'sync_ws_disconnects_total',
      help: 'WS connections closed',
      registers: [this.registry],
    });
  }

  observeHttp(method: string, route: string, status: number, durationMs: number): void {
    const labels = { method, route, status: String(status) };
    this.httpRequestsTotal.inc(labels, 1);
    this.httpRequestDurationMs.observe(labels, durationMs);
  }

  recordEventsAccepted(count: number): void {
    this.syncEventsAccepted.inc(count);
  }

  recordEventsDuplicate(count: number): void {
    this.syncEventsDuplicate.inc(count);
  }

  recordEventsRejected(count: number): void {
    this.syncEventsRejected.inc(count);
  }

  recordEventsPulled(count: number): void {
    this.syncEventsPulled.inc(count);
  }

  recordStateUpdate(count: number): void {
    this.syncStateUpdates.inc(count);
  }

  recordWsConnected(): void {
    this.syncWsConnected.inc(1);
  }

  recordWsDisconnected(): void {
    this.syncWsDisconnects.inc(1);
  }

  async metrics(): Promise<string> {
    return this.registry.metrics();
  }
}

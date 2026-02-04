import { Injectable } from '@nestjs/common';
import { EventEmitter } from 'node:events';

export type EventsAvailablePayload = {
  userId: string;
  serverCursor: string;
};

@Injectable()
export class SyncEventsBus {
  private readonly emitter = new EventEmitter();

  constructor() {
    this.emitter.setMaxListeners(0);
  }

  emitEventsAvailable(payload: EventsAvailablePayload): void {
    this.emitter.emit('events_available', payload);
  }

  onEventsAvailable(
    listener: (payload: EventsAvailablePayload) => void,
  ): () => void {
    this.emitter.on('events_available', listener);
    return () => this.emitter.off('events_available', listener);
  }
}

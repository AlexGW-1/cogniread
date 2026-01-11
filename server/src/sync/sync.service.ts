import { Injectable } from '@nestjs/common';
import { EventLogEntryDto } from './dto/event-log-entry.dto';

@Injectable()
export class SyncService {
  private readonly events: EventLogEntryDto[] = [];

  append(events: EventLogEntryDto[]): void {
    this.events.push(...events);
  }

  list(cursor?: string, limit = 200): { events: EventLogEntryDto[]; cursor: string } {
    const offset = cursor ? Number(cursor) : 0;
    const slice = this.events.slice(offset, offset + limit);
    const nextCursor = String(offset + slice.length);
    return { events: slice, cursor: nextCursor };
  }
}

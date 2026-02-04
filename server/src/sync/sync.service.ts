import {
  BadRequestException,
  Injectable,
  UnprocessableEntityException,
} from '@nestjs/common';
import { EventLogEntryDto } from './dto/event-log-entry.dto';
import { AckDto } from './dto/upload-events.dto';
import { SyncRepository } from './sync.repository';
import { SyncEventsBus } from './sync.events';
import { ReadingPositionDto } from './dto/reading-position.dto';
import { decodeCursor } from './sync.cursor';
import { MetricsService } from '../observability/metrics.service';
import { JsonLogger } from '../observability/logger.service';
import { getTraceContext } from '../observability/trace.util';

const SUPPORTED_SCHEMA_VERSION = 1;

@Injectable()
export class SyncService {
  constructor(
    private readonly repo: SyncRepository,
    private readonly eventsBus: SyncEventsBus,
    private readonly metrics: MetricsService,
    private readonly logger: JsonLogger,
  ) {}

  async appendEvents(
    userId: string,
    deviceId: string,
    cursor: string | null | undefined,
    events: EventLogEntryDto[],
  ): Promise<{ acks: AckDto[]; serverCursor: string }> {
    const traceContext = getTraceContext();
    this.logger.log('sync.upload', {
      userId,
      deviceId,
      cursor,
      count: events.length,
      ...traceContext,
    });
    if (cursor) {
      await this.repo.upsertDeviceCursor(userId, deviceId, cursor);
    }

    const existingIds = await this.repo.findExistingEventIds(
      events.map((event) => event.id),
    );

    const acks: AckDto[] = [];
    const acceptedEvents: EventLogEntryDto[] = [];

    for (const event of events) {
      if (event.schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
        acks.push({
          id: event.id,
          status: 'rejected',
          reason: 'unsupported_schema_version',
        });
        continue;
      }
      if (existingIds.has(event.id)) {
        acks.push({ id: event.id, status: 'duplicate' });
        continue;
      }
      acceptedEvents.push(event);
      acks.push({ id: event.id, status: 'accepted' });
    }

    await this.repo.insertEvents(userId, deviceId, acceptedEvents);
    if (acks.length > 0) {
      const acceptedCount = acceptedEvents.length;
      const duplicateCount = acks.filter((ack) => ack.status === 'duplicate').length;
      const rejectedCount = acks.filter((ack) => ack.status === 'rejected').length;
      this.metrics.recordEventsAccepted(acceptedCount);
      this.metrics.recordEventsDuplicate(duplicateCount);
      this.metrics.recordEventsRejected(rejectedCount);
      this.logger.log('sync.ack', {
        userId,
        deviceId,
        accepted: acceptedCount,
        duplicate: duplicateCount,
        rejected: rejectedCount,
        ...traceContext,
      });
    }

    const serverCursor = await this.repo.getLatestCursor(userId);
    if (acceptedEvents.length > 0 && serverCursor) {
      this.eventsBus.emitEventsAvailable({ userId, serverCursor });
    }
    return { acks, serverCursor };
  }

  async listEvents(
    userId: string,
    cursor: string | null | undefined,
    limit: number,
  ): Promise<{ events: EventLogEntryDto[]; serverCursor: string }> {
    try {
      const result = await this.repo.listEvents(userId, cursor, limit);
      this.metrics.recordEventsPulled(result.events.length);
      this.logger.log('sync.pull', {
        userId,
        cursor,
        limit,
        returned: result.events.length,
        ...getTraceContext(),
      });
      return result;
    } catch (error) {
      if (error instanceof Error && error.message === 'invalid_cursor') {
        throw new BadRequestException('Invalid cursor');
      }
      throw error;
    }
  }

  async uploadState(
    userId: string,
    deviceId: string,
    lastSeenCursor: string | null | undefined,
    readingPositions: ReadingPositionDto[],
    schemaVersion: number,
  ): Promise<void> {
    const traceContext = getTraceContext();
    this.logger.log('sync.state', {
      userId,
      deviceId,
      lastSeenCursor,
      count: readingPositions.length,
      schemaVersion,
      ...traceContext,
    });
    if (schemaVersion !== SUPPORTED_SCHEMA_VERSION) {
      throw new UnprocessableEntityException('unsupported_schema_version');
    }
    const normalizedCursor =
      typeof lastSeenCursor === 'string' ? lastSeenCursor.trim() : lastSeenCursor;
    if (normalizedCursor && !decodeCursor(normalizedCursor)) {
      throw new BadRequestException('Invalid cursor');
    }
    if (normalizedCursor) {
      await this.repo.upsertDeviceCursor(userId, deviceId, normalizedCursor);
    }
    await this.repo.upsertReadingPositions(
      userId,
      readingPositions.map((pos) => ({
        bookId: pos.bookId,
        chapterHref: pos.chapterHref ?? null,
        anchor: pos.anchor ?? null,
        offset: pos.offset ?? null,
        updatedAt: pos.updatedAt,
      })),
    );
    this.metrics.recordStateUpdate(readingPositions.length);
  }
}

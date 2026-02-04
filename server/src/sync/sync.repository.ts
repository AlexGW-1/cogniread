import { Injectable } from '@nestjs/common';
import { Prisma, PrismaService } from '../prisma/prisma.service';
import { EventLogEntryDto } from './dto/event-log-entry.dto';
import { decodeCursor, encodeCursor } from './sync.cursor';

export type EventLogCursor = {
  createdAt: Date;
  id: string;
};

@Injectable()
export class SyncRepository {
  constructor(private readonly prisma: PrismaService) {}

  async listEvents(
    userId: string,
    cursor: string | null | undefined,
    limit: number,
  ): Promise<{ events: EventLogEntryDto[]; serverCursor: string }>{
    const decoded = decodeCursor(cursor);
    if (cursor && !decoded) {
      throw new Error('invalid_cursor');
    }

    const where = decoded
      ? {
          userId,
          OR: [
            { createdAt: { gt: new Date(decoded.createdAt) } },
            {
              createdAt: new Date(decoded.createdAt),
              id: { gt: decoded.id },
            },
          ],
        }
      : { userId };

    const events = await this.prisma.eventLog.findMany({
      where,
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      take: limit,
    });

    const mapped = events.map((event) => ({
      id: event.id,
      entityType: event.entityType,
      entityId: event.entityId,
      op: event.op,
      payload: event.payload as Record<string, unknown>,
      createdAt: event.createdAt.toISOString(),
      schemaVersion: event.schemaVersion,
    }));

    let serverCursor = cursor ?? '';
    if (events.length > 0) {
      const last = events[events.length - 1];
      serverCursor = encodeCursor(last.createdAt, last.id);
    }

    return { events: mapped, serverCursor };
  }

  async getLatestCursor(userId: string): Promise<string> {
    const latest = await this.prisma.eventLog.findFirst({
      where: { userId },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    });
    if (!latest) {
      return '';
    }
    return encodeCursor(latest.createdAt, latest.id);
  }

  async findExistingEventIds(ids: string[]): Promise<Set<string>> {
    if (ids.length === 0) {
      return new Set();
    }
    const existing = await this.prisma.eventLog.findMany({
      where: { id: { in: ids } },
      select: { id: true },
    });
    return new Set(existing.map((item) => item.id));
  }

  async insertEvents(
    userId: string,
    deviceId: string,
    events: EventLogEntryDto[],
  ): Promise<void> {
    if (events.length === 0) {
      return;
    }
    await this.prisma.eventLog.createMany({
      data: events.map((event) => ({
        id: event.id,
        userId,
        deviceId,
        entityType: event.entityType,
        entityId: event.entityId,
        op: event.op,
        payload: event.payload as Prisma.InputJsonValue,
        createdAt: new Date(event.createdAt),
        schemaVersion: event.schemaVersion,
      })),
      skipDuplicates: true,
    });
  }

  async upsertDeviceCursor(
    userId: string,
    deviceId: string,
    cursor: string,
  ): Promise<void> {
    const now = new Date();
    await this.prisma.syncCursor.upsert({
      where: { userId_deviceId: { userId, deviceId } },
      update: { lastCursor: cursor, updatedAt: now },
      create: { userId, deviceId, lastCursor: cursor, updatedAt: now },
    });
  }

  async upsertReadingPositions(
    userId: string,
    positions: Array<{
      bookId: string;
      chapterHref?: string | null;
      anchor?: string | null;
      offset?: number | null;
      updatedAt: string;
    }>,
  ): Promise<void> {
    if (positions.length === 0) {
      return;
    }
    await this.prisma.$transaction(
      positions.map((position) =>
        this.prisma.readingPosition.upsert({
          where: { userId_bookId: { userId, bookId: position.bookId } },
          update: {
            chapterHref: position.chapterHref ?? null,
            anchor: position.anchor ?? null,
            offset: position.offset ?? null,
            updatedAt: new Date(position.updatedAt),
          },
          create: {
            userId,
            bookId: position.bookId,
            chapterHref: position.chapterHref ?? null,
            anchor: position.anchor ?? null,
            offset: position.offset ?? null,
            updatedAt: new Date(position.updatedAt),
          },
        }),
      ),
    );
  }
}

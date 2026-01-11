import { Controller, Get, Query, Post, Body, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from './sync.guard';
import { SyncService } from './sync.service';
import {
  UploadEventsRequestDto,
  UploadEventsResponseDto,
  AckDto,
} from './dto/upload-events.dto';
import { PullEventsResponseDto } from './dto/pull-events.dto';

@UseGuards(JwtAuthGuard)
@Controller('sync')
export class SyncController {
  constructor(private readonly service: SyncService) {}

  @Post('events')
  uploadEvents(@Body() body: UploadEventsRequestDto): UploadEventsResponseDto {
    const acks: AckDto[] = body.events.map((event) => ({
      id: event.id,
      status: 'accepted',
    }));
    this.service.append(body.events);
    return {
      apiVersion: 'v0.1',
      accepted: acks,
      serverCursor: String(this.service.list().cursor),
    };
  }

  @Get('events')
  pullEvents(
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ): PullEventsResponseDto {
    const parsedLimit = limit ? Number(limit) : 200;
    const { events, cursor: serverCursor } = this.service.list(
      cursor,
      parsedLimit,
    );
    return {
      apiVersion: 'v0.1',
      events,
      serverCursor,
    };
  }
}

import { Controller, Get, Query, Post, Body, UseGuards, Req } from '@nestjs/common';
import { Request } from 'express';
import { JwtAuthGuard } from './sync.guard';
import { SyncService } from './sync.service';
import {
  UploadEventsRequestDto,
  UploadEventsResponseDto,
} from './dto/upload-events.dto';
import { PullEventsResponseDto } from './dto/pull-events.dto';
import {
  UploadStateRequestDto,
  UploadStateResponseDto,
} from './dto/upload-state.dto';

@UseGuards(JwtAuthGuard)
@Controller('sync')
export class SyncController {
  constructor(private readonly service: SyncService) {}

  @Post('events')
  async uploadEvents(
    @Req() request: Request & { userId?: string },
    @Body() body: UploadEventsRequestDto,
  ): Promise<UploadEventsResponseDto> {
    const userId = request.userId ?? '';
    const { acks, serverCursor } = await this.service.appendEvents(
      userId,
      body.deviceId,
      body.cursor,
      body.events,
    );
    return {
      apiVersion: 'v0.1',
      accepted: acks,
      serverCursor,
    };
  }

  @Get('events')
  async pullEvents(
    @Req() request: Request & { userId?: string },
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
  ): Promise<PullEventsResponseDto> {
    const userId = request.userId ?? '';
    const parsedLimit = limit ? Number(limit) : 200;
    const normalizedLimit =
      Number.isFinite(parsedLimit) && parsedLimit > 0
        ? Math.min(parsedLimit, 200)
        : 200;
    const { events, serverCursor } = await this.service.listEvents(
      userId,
      cursor,
      normalizedLimit,
    );
    return {
      apiVersion: 'v0.1',
      events,
      serverCursor,
    };
  }

  @Post('state')
  async uploadState(
    @Req() request: Request & { userId?: string },
    @Body() body: UploadStateRequestDto,
  ): Promise<UploadStateResponseDto> {
    const userId = request.userId ?? '';
    await this.service.uploadState(
      userId,
      body.deviceId,
      body.lastSeenCursor,
      body.readingPositions,
      body.schemaVersion,
    );
    return { apiVersion: 'v0.1', status: 'ok' };
  }
}

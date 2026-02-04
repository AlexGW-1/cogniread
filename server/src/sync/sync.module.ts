import { Module } from '@nestjs/common';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';
import { PrismaService } from '../prisma/prisma.service';
import { SyncRepository } from './sync.repository';
import { SyncEventsBus } from './sync.events';
import { SyncWsGateway } from './sync.ws';
import { ObservabilityModule } from '../observability/observability.module';

@Module({
  imports: [ObservabilityModule],
  controllers: [SyncController],
  providers: [PrismaService, SyncRepository, SyncEventsBus, SyncService, SyncWsGateway],
})
export class SyncModule {}

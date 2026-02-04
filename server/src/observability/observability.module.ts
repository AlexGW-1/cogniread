import { Module } from '@nestjs/common';
import { JsonLogger } from './logger.service';
import { MetricsController } from './metrics.controller';
import { MetricsService } from './metrics.service';
import { RequestIdMiddleware } from './request-id.middleware';

@Module({
  controllers: [MetricsController],
  providers: [JsonLogger, MetricsService, RequestIdMiddleware],
  exports: [JsonLogger, MetricsService, RequestIdMiddleware],
})
export class ObservabilityModule {}

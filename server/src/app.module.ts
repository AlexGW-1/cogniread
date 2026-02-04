import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { SyncModule } from './sync/sync.module';
import { ObservabilityModule } from './observability/observability.module';
import { RequestIdMiddleware } from './observability/request-id.middleware';
import { StorageModule } from './storage/storage.module';

@Module({
  imports: [ObservabilityModule, SyncModule, StorageModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(RequestIdMiddleware).forRoutes('*');
  }
}

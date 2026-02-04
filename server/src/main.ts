import './observability/otel';
import { NestFactory } from '@nestjs/core';
import { UnprocessableEntityException, ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import { JsonLogger } from './observability/logger.service';
import { LoggingInterceptor } from './observability/logging.interceptor';
import { MetricsService } from './observability/metrics.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  const logger = app.get(JsonLogger);
  const metrics = app.get(MetricsService);
  app.useLogger(logger);
  app.useGlobalInterceptors(new LoggingInterceptor(logger, metrics));
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
      exceptionFactory: (errors) => new UnprocessableEntityException(errors),
    }),
  );
  const port = Number(process.env.PORT ?? 3000);
  const host = process.env.HOST ?? '0.0.0.0';
  await app.listen(port, host);
}
bootstrap();

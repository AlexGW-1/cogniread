import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import dotenv from "dotenv";
import { AppModule } from "./modules/app/app.module.js";

dotenv.config();

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { cors: true });

  const config = new DocumentBuilder()
    .setTitle("CogniRead API")
    .setDescription("MVP skeleton (NestJS)")
    .setVersion("v1")
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup("/docs", app, document);

  const port = Number(process.env.PORT ?? 8080);
  await app.listen(port, "0.0.0.0");
  // eslint-disable-next-line no-console
  console.log(`[api] listening on :${port}`);
}

bootstrap();

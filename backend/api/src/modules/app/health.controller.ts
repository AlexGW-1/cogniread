import { Controller, Get } from "@nestjs/common";
import { ApiOkResponse, ApiTags } from "@nestjs/swagger";

@ApiTags("system")
@Controller()
export class HealthController {
  @Get("/health")
  @ApiOkResponse({ description: "API healthcheck" })
  health() {
    return { ok: true, service: "api", ts: new Date().toISOString() };
  }

  @Get("/v1/books")
  listBooks() {
    return { items: [], note: "TODO: implement (stub)" };
  }

  @Get("/v1/notes")
  listNotes() {
    return { items: [], note: "TODO: implement (stub)" };
  }
}

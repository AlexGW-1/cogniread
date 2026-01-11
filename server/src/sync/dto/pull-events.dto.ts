import { IsArray, IsString, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';
import { EventLogEntryDto } from './event-log-entry.dto';

export class PullEventsResponseDto {
  @IsString()
  apiVersion: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => EventLogEntryDto)
  events: EventLogEntryDto[];

  @IsString()
  serverCursor: string;
}

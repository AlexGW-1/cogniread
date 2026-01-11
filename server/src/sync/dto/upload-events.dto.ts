import {
  ArrayMaxSize,
  IsArray,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { EventLogEntryDto } from './event-log-entry.dto';

export class UploadEventsRequestDto {
  @IsString()
  deviceId: string;

  @IsOptional()
  @IsString()
  cursor?: string | null;

  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => EventLogEntryDto)
  events: EventLogEntryDto[];
}

export class AckDto {
  @IsString()
  id: string;

  @IsString()
  status: string;

  @IsOptional()
  @IsString()
  reason?: string;
}

export class UploadEventsResponseDto {
  @IsString()
  apiVersion: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => AckDto)
  accepted: AckDto[];

  @IsString()
  serverCursor: string;
}

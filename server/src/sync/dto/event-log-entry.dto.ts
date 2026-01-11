import { IsDateString, IsIn, IsInt, IsObject, IsString } from 'class-validator';

export class EventLogEntryDto {
  @IsString()
  id: string;

  @IsString()
  entityType: string;

  @IsString()
  entityId: string;

  @IsIn(['add', 'update', 'delete'])
  op: string;

  @IsObject()
  payload: Record<string, unknown>;

  @IsDateString()
  createdAt: string;

  @IsInt()
  schemaVersion: number;
}

import {
  ArrayMaxSize,
  IsArray,
  IsInt,
  IsNotEmpty,
  IsOptional,
  IsString,
  ValidateNested,
} from 'class-validator';
import { Type } from 'class-transformer';
import { ReadingPositionDto } from './reading-position.dto';

export class UploadStateRequestDto {
  @IsNotEmpty()
  @IsString()
  deviceId: string;

  @IsOptional()
  @IsString()
  lastSeenCursor?: string | null;

  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => ReadingPositionDto)
  readingPositions: ReadingPositionDto[];

  @IsInt()
  schemaVersion: number;
}

export class UploadStateResponseDto {
  @IsString()
  apiVersion: string;

  @IsString()
  status: string;
}

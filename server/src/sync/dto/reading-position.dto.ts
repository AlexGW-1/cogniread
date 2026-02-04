import { IsDateString, IsInt, IsOptional, IsString } from 'class-validator';

export class ReadingPositionDto {
  @IsString()
  bookId: string;

  @IsOptional()
  @IsString()
  chapterHref?: string | null;

  @IsOptional()
  @IsString()
  anchor?: string | null;

  @IsOptional()
  @IsInt()
  offset?: number | null;

  @IsDateString()
  updatedAt: string;
}

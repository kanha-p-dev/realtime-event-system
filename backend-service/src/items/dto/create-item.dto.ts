import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class CreateItemDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;
}

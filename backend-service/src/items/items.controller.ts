import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Param,
  Patch,
  Post,
} from '@nestjs/common';
import { CreateItemDto } from './dto/create-item.dto';
import { ItemsService } from './items.service';
import { Item } from './schemas/item.schema';

@Controller('items')
export class ItemsController {
  constructor(private readonly itemsService: ItemsService) {}

  @Post()
  async create(
    @Body() createItemDto: CreateItemDto,
    @Headers('x-channel-id') channelId?: string,
  ): Promise<Item> {
    return this.itemsService.create(createItemDto, channelId);
  }

  @Get()
  async findAll(@Headers('x-channel-id') channelId?: string): Promise<Item[]> {
    return this.itemsService.findAll(channelId);
  }

  @Patch(':id/ts')
  async refreshTs(
    @Param('id') id: string,
    @Headers('x-channel-id') channelId?: string,
  ): Promise<Item> {
    return this.itemsService.refreshTs(id, channelId);
  }

  @Delete(':id')
  async remove(
    @Param('id') id: string,
    @Headers('x-channel-id') channelId?: string,
  ): Promise<Item> {
    return this.itemsService.remove(id, channelId);
  }
}

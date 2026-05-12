import { Body, Controller, Get, Param, Patch, Post } from '@nestjs/common';
import { CreateItemDto } from './dto/create-item.dto';
import { ItemsService } from './items.service';
import { Item } from './schemas/item.schema';

@Controller('items')
export class ItemsController {
  constructor(private readonly itemsService: ItemsService) {}

  @Post()
  async create(@Body() createItemDto: CreateItemDto): Promise<Item> {
    return this.itemsService.create(createItemDto);
  }

  @Get()
  async findAll(): Promise<Item[]> {
    return this.itemsService.findAll();
  }

  @Patch(':id/ts')
  async refreshTs(@Param('id') id: string): Promise<Item> {
    return this.itemsService.refreshTs(id);
  }
}

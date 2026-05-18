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
    // รับ channel/client จาก header แล้วส่งต่อให้ service จัดการ validation
    @Headers('x-channel-id') channelId?: string,
    @Headers('x-client-id') clientId?: string,
  ): Promise<Item> {
    return this.itemsService.create(createItemDto, channelId, clientId);
  }

  @Get()
  async findAll(@Headers('x-channel-id') channelId?: string): Promise<Item[]> {
    return this.itemsService.findAll(channelId);
  }

  @Patch(':id/ts')
  async refreshTs(
    @Param('id') id: string,
    // ใช้ channel เดิมในการจำกัดขอบเขตข้อมูล และ client สำหรับระบุที่มาของการแก้ไข
    @Headers('x-channel-id') channelId?: string,
    @Headers('x-client-id') clientId?: string,
  ): Promise<Item> {
    return this.itemsService.refreshTs(id, channelId, clientId);
  }

  @Delete(':id')
  async remove(
    @Param('id') id: string,
    // ลบแบบ soft delete โดยระบุผู้แก้ไขล่าสุดผ่าน clientId
    @Headers('x-channel-id') channelId?: string,
    @Headers('x-client-id') clientId?: string,
  ): Promise<Item> {
    return this.itemsService.remove(id, channelId, clientId);
  }
}

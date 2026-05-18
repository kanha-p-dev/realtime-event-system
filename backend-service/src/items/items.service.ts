import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { CreateItemDto } from './dto/create-item.dto';
import { Item, ItemDocument } from './schemas/item.schema';

@Injectable()
export class ItemsService {
  private readonly logger = new Logger(ItemsService.name);
  // channel ใช้เบอร์โทรไทยรูปแบบ 0XXXXXXXXX
  private static readonly channelIdRegex = /^0\d{9}$/;
  // clientId รองรับตัวอักษรที่ปลอดภัยสำหรับ log/query string
  private static readonly clientIdRegex = /^[a-zA-Z0-9:_-]{6,120}$/;

  constructor(
    @InjectModel(Item.name) private readonly itemModel: Model<ItemDocument>,
  ) {}

  async create(
    createItemDto: CreateItemDto,
    channelId?: string,
    clientId?: string,
  ): Promise<Item> {
    const normalizedChannelId = this.requireChannelId(channelId);
    const normalizedClientId = this.normalizeClientId(clientId);

    const item = new this.itemModel({
      name: createItemDto.name,
      ts: new Types.ObjectId(),
      ownerChannelId: normalizedChannelId,
      lastUpdatedByChannel: normalizedChannelId,
      lastUpdatedByClient: normalizedClientId,
    });
    const savedItem = await item.save();
    this.logger.log(
      `create_item success itemId=${String(savedItem._id)} newTs=${String(savedItem.ts)} channelId=${normalizedChannelId ?? 'none'}`,
    );
    return savedItem;
  }

  async findAll(channelId?: string): Promise<Item[]> {
    const normalizedChannelId = this.requireChannelId(channelId);

    // อ่านเฉพาะข้อมูลใน channel เดียวกัน และซ่อนรายการที่ถูกลบแล้ว
    const items = await this.itemModel
      .find({
        ownerChannelId: normalizedChannelId,
        $or: [{ deletedAt: null }, { deletedAt: { $exists: false } }],
      })
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
    this.logger.log(
      `list_items success count=${items.length} channelId=${normalizedChannelId}`,
    );
    return items;
  }

  async refreshTs(
    id: string,
    channelId?: string,
    clientId?: string,
  ): Promise<Item> {
    if (!Types.ObjectId.isValid(id)) {
      this.logger.warn(`refresh_item_ts invalid_id id=${id}`);
      throw new NotFoundException('Item not found');
    }

    const normalizedChannelId = this.requireChannelId(channelId);
    const normalizedClientId = this.normalizeClientId(clientId);

    // อัปเดต ts ทุกครั้งเพื่อให้ฝั่ง realtime มองเห็นการเปลี่ยนแปลงแน่นอน
    const updatedItem = await this.itemModel
      .findOneAndUpdate(
        {
          _id: id,
          ownerChannelId: normalizedChannelId,
          $or: [{ deletedAt: null }, { deletedAt: { $exists: false } }],
        },
        {
          $set: {
            ts: new Types.ObjectId(),
            lastUpdatedByChannel: normalizedChannelId,
            lastUpdatedByClient: normalizedClientId,
          },
        },
        { returnDocument: 'after', runValidators: true },
      )
      .lean()
      .exec();

    if (!updatedItem) {
      this.logger.warn(`refresh_item_ts not_found id=${id}`);
      throw new NotFoundException('Item not found');
    }

    this.logger.log(
      `refresh_item_ts success itemId=${String(updatedItem._id)} newTs=${String(updatedItem.ts)} channelId=${normalizedChannelId ?? 'none'}`,
    );
    return updatedItem;
  }

  async remove(
    id: string,
    channelId?: string,
    clientId?: string,
  ): Promise<Item> {
    if (!Types.ObjectId.isValid(id)) {
      this.logger.warn(`delete_item invalid_id id=${id}`);
      throw new NotFoundException('Item not found');
    }

    const normalizedChannelId = this.requireChannelId(channelId);
    const normalizedClientId = this.normalizeClientId(clientId);

    // ใช้ soft delete และขยับ ts เพื่อกระตุ้น event realtime ฝั่ง gateway
    const deletedItem = await this.itemModel
      .findOneAndUpdate(
        {
          _id: id,
          ownerChannelId: normalizedChannelId,
          $or: [{ deletedAt: null }, { deletedAt: { $exists: false } }],
        },
        {
          $set: {
            deletedAt: new Date(),
            ts: new Types.ObjectId(),
            lastUpdatedByChannel: normalizedChannelId,
            lastUpdatedByClient: normalizedClientId,
          },
        },
        { returnDocument: 'after', runValidators: true },
      )
      .lean()
      .exec();

    if (!deletedItem) {
      this.logger.warn(`delete_item not_found id=${id}`);
      throw new NotFoundException('Item not found');
    }

    this.logger.log(
      `delete_item success itemId=${String(deletedItem._id)} channelId=${normalizedChannelId ?? 'none'}`,
    );

    return deletedItem;
  }

  private requireChannelId(channelId?: string): string {
    // บังคับให้ทุกคำขอระบุ channel เสมอ ป้องกันข้อมูลข้ามห้อง
    if (!channelId) {
      throw new BadRequestException('Missing x-channel-id header');
    }

    const trimmed = channelId.trim();
    if (!ItemsService.channelIdRegex.test(trimmed)) {
      throw new BadRequestException(
        'Invalid x-channel-id header (Thai phone format: 0XXXXXXXXX)',
      );
    }

    return trimmed;
  }

  private normalizeClientId(clientId?: string): string | undefined {
    // clientId เป็น optional แต่ถ้าส่งมาต้องผ่านรูปแบบที่กำหนด
    if (!clientId) {
      return undefined;
    }

    const trimmed = clientId.trim();
    if (!trimmed) {
      return undefined;
    }

    if (!ItemsService.clientIdRegex.test(trimmed)) {
      throw new BadRequestException('Invalid x-client-id header');
    }

    return trimmed;
  }
}

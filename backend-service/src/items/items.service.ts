import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { CreateItemDto } from './dto/create-item.dto';
import { Item, ItemDocument } from './schemas/item.schema';

@Injectable()
export class ItemsService {
  private readonly logger = new Logger(ItemsService.name);
  private static readonly channelIdRegex = /^[a-zA-Z0-9_-]{6,120}$/;

  constructor(
    @InjectModel(Item.name) private readonly itemModel: Model<ItemDocument>,
  ) {}

  async create(
    createItemDto: CreateItemDto,
    channelId?: string,
  ): Promise<Item> {
    const normalizedChannelId = this.normalizeChannelId(channelId);

    const item = new this.itemModel({
      name: createItemDto.name,
      ts: new Types.ObjectId(),
      lastUpdatedByChannel: normalizedChannelId,
    });
    const savedItem = await item.save();
    this.logger.log(
      `create_item success itemId=${String(savedItem._id)} newTs=${String(savedItem.ts)} channelId=${normalizedChannelId ?? 'none'}`,
    );
    return savedItem;
  }

  async findAll(): Promise<Item[]> {
    const items = await this.itemModel
      .find()
      .sort({ updatedAt: -1 })
      .lean()
      .exec();
    this.logger.log(`list_items success count=${items.length}`);
    return items;
  }

  async refreshTs(id: string, channelId?: string): Promise<Item> {
    if (!Types.ObjectId.isValid(id)) {
      this.logger.warn(`refresh_item_ts invalid_id id=${id}`);
      throw new NotFoundException('Item not found');
    }

    const normalizedChannelId = this.normalizeChannelId(channelId);

    const updatedItem = await this.itemModel
      .findByIdAndUpdate(
        id,
        {
          $set: {
            ts: new Types.ObjectId(),
            lastUpdatedByChannel: normalizedChannelId,
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

  private normalizeChannelId(channelId?: string): string | undefined {
    if (!channelId) {
      return undefined;
    }

    const trimmed = channelId.trim();
    if (!ItemsService.channelIdRegex.test(trimmed)) {
      return undefined;
    }

    return trimmed;
  }
}

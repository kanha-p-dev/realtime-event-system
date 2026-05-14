import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type ItemDocument = HydratedDocument<Item>;

@Schema({ collection: 'items', timestamps: true, toJSON: { virtuals: true } })
export class Item {
  @Prop({ required: true, trim: true })
  name!: string;

  @Prop({ required: true, default: () => new Types.ObjectId() })
  ts!: Types.ObjectId;

  @Prop({ required: false, trim: true, maxlength: 120 })
  lastUpdatedByChannel?: string;

  @Prop({ type: Date, required: false })
  deletedAt?: Date;
}

export const ItemSchema = SchemaFactory.createForClass(Item);

ItemSchema.virtual('tsFormatted').get(function () {
  if (!this.ts) return null;
  const timestamp = this.ts.getTimestamp();
  return new Intl.DateTimeFormat('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: true,
  }).format(timestamp);
});

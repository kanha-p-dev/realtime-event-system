import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { InjectConnection } from '@nestjs/mongoose';
import type { Connection } from 'mongoose';
import { Document, Types } from 'mongoose';
import type { EventEmitter } from 'node:events';
import { randomUUID } from 'node:crypto';
import { RealtimeGateway } from './realtime.gateway';

const BROADCAST_LOCK_COLLECTION = 'realtime_broadcast_locks';
const BROADCAST_LOCK_ID = 'ts_changed';
const BROADCAST_LOCK_TTL_MS = 15_000;
const BROADCAST_LOCK_RENEW_MS = 5_000;
const FLUSH_DEBOUNCE_MS = 50;

interface ItemChangeDocument extends Document {
  _id: Types.ObjectId;
  ts?: Types.ObjectId | string | { $oid: string };
  lastUpdatedByChannel?: string;
  lastUpdatedByClient?: string;
  deletedAt?: Date | null;
}

interface PendingChangePayload {
  ts: ExtendedObjectId;
  channelId?: string;
  clientId?: string;
  deleted: boolean;
}

interface ItemChangeEvent {
  documentKey: { _id: Types.ObjectId };
  fullDocument?: ItemChangeDocument;
  operationType: string;
}

interface BroadcastLockDocument {
  _id: string;
  source: string;
  expiresAt: Date;
  updatedAt: Date;
  createdAt: Date;
}

interface ExtendedObjectId {
  $oid: string;
}

interface ChangeStreamEmitter extends EventEmitter {
  close(): Promise<void>;
}

@Injectable()
export class ChangeStreamService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ChangeStreamService.name);
  private changeStream?: ChangeStreamEmitter;
  private readonly pendingChanges = new Map<string, PendingChangePayload>();
  // เก็บ event ชั่วคราวเพื่อ batch ก่อน broadcast
  private flushTimer?: NodeJS.Timeout;
  private lockRenewTimer?: NodeJS.Timeout;
  // มีเพียง instance ที่เป็น leader เท่านั้นที่อนุญาตให้ broadcast
  private hasBroadcastLeadership = false;
  private readonly sourceId = `${process.pid}-${randomUUID()}`;

  constructor(
    @InjectConnection() private readonly connection: Connection,
    private readonly realtimeGateway: RealtimeGateway,
  ) {}

  async onModuleInit(): Promise<void> {
    const collection = this.connection.collection<ItemChangeDocument>('items');
    await this.ensureLockIndexes();
    await this.tryAcquireBroadcastLeadership();
    this.startLockRenewLoop();

    // watch การเปลี่ยนแปลง collection items แล้วแปลงเป็น event สำหรับ websocket
    this.changeStream = collection.watch([], {
      fullDocument: 'updateLookup',
    });

    if (this.changeStream) {
      this.changeStream.on('change', (change: ItemChangeEvent) =>
        this.handleChange(change),
      );
      this.changeStream.on('error', (error: Error) => {
        this.logger.error(`Change stream error: ${error.message}`);
      });
    }

    this.logger.log(`Change stream watcher started (source=${this.sourceId})`);
  }

  async onModuleDestroy(): Promise<void> {
    if (this.lockRenewTimer) {
      clearInterval(this.lockRenewTimer);
      this.lockRenewTimer = undefined;
    }

    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = undefined;
    }

    if (this.changeStream) {
      this.logger.log('Closing change stream watcher');
      await this.changeStream.close();
    }
  }

  private handleChange(change: ItemChangeEvent): void {
    if (!this.shouldProcessOperation(change.operationType)) {
      return;
    }

    const normalizedId = this.normalizeObjectId(change.documentKey._id);
    const normalizedTs =
      this.extractTsFromDocument(change.fullDocument) ?? normalizedId;
    const channelId = this.extractChannelIdFromDocument(change.fullDocument);
    const clientId = this.extractClientIdFromDocument(change.fullDocument);

    if (!normalizedId || !normalizedTs) {
      this.logger.warn('Skipping change event with invalid ObjectId payload');
      return;
    }

    this.logger.debug(
      `handleChange operationType=${change.operationType} itemId=${normalizedId} channelId=${channelId ?? 'undefined'} clientId=${clientId ?? 'undefined'} lastUpdatedByChannel=${change.fullDocument?.lastUpdatedByChannel}`,
    );

    this.enqueueChange(normalizedId, {
      ts: { $oid: normalizedTs },
      channelId,
      clientId,
      deleted: this.isDeletedDocument(change.fullDocument),
    });
  }

  private enqueueChange(id: string, payload: PendingChangePayload): void {
    this.pendingChanges.set(id, payload);

    if (this.flushTimer) {
      return;
    }

    this.logger.debug(
      `Scheduling change stream flush with ${this.pendingChanges.size} pending item(s)`,
    );

    // รวม event ที่มาถี่ ๆ ภายในช่วงสั้น เพื่อลดจำนวน emit ที่ไม่จำเป็น
    this.flushTimer = setTimeout(() => {
      this.flushPendingChanges();
    }, FLUSH_DEBOUNCE_MS);
  }

  private flushPendingChanges(): void {
    const batchSize = this.pendingChanges.size;

    if (!this.hasBroadcastLeadership) {
      // ถ้าไม่ได้สิทธิ์ leader จะไม่ broadcast ป้องกันซ้ำเมื่อมีหลาย replica
      this.logger.debug(
        `Skipping flush of ${batchSize} event(s) because source is not leader`,
      );
      this.pendingChanges.clear();
      this.flushTimer = undefined;
      return;
    }

    for (const [id, changePayload] of this.pendingChanges.entries()) {
      this.logger.debug(
        `Broadcasting ts_changed itemId=${id} channelId=${changePayload.channelId ?? 'undefined'} clientId=${changePayload.clientId ?? 'undefined'}`,
      );
      this.realtimeGateway.broadcastTsChanged({
        id,
        ts: changePayload.ts,
        source: this.sourceId,
        channelId: changePayload.channelId,
        clientId: changePayload.clientId,
        deleted: changePayload.deleted,
      });
    }

    this.logger.debug(
      `Flushed ${batchSize} change stream event(s) to websocket`,
    );

    this.pendingChanges.clear();
    this.flushTimer = undefined;
  }

  private shouldProcessOperation(operationType: string): boolean {
    return (
      operationType === 'insert' ||
      operationType === 'update' ||
      operationType === 'replace' ||
      operationType === 'delete'
    );
  }

  private extractTsFromDocument(
    document?: ItemChangeDocument,
  ): string | undefined {
    if (!document) {
      return undefined;
    }

    return this.normalizeObjectId(document.ts);
  }

  private extractChannelIdFromDocument(
    document?: ItemChangeDocument,
  ): string | undefined {
    if (!document?.lastUpdatedByChannel) {
      return undefined;
    }

    return this.normalizeChannelId(document.lastUpdatedByChannel);
  }

  private extractClientIdFromDocument(
    document?: ItemChangeDocument,
  ): string | undefined {
    const rawClientId = document?.lastUpdatedByClient;
    if (!rawClientId) {
      return undefined;
    }

    const trimmed = rawClientId.trim();
    if (!trimmed) {
      return undefined;
    }

    return trimmed;
  }

  private normalizeChannelId(value: string): string | undefined {
    const trimmed = value.trim();
    if (!/^0\d{9}$/.test(trimmed)) {
      return undefined;
    }

    return trimmed;
  }

  private isDeletedDocument(document?: ItemChangeDocument): boolean {
    return Boolean(document?.deletedAt);
  }

  private normalizeObjectId(value: unknown): string | undefined {
    if (value instanceof Types.ObjectId) {
      return value.toHexString();
    }

    if (typeof value === 'string') {
      return /^[a-fA-F0-9]{24}$/.test(value) ? value.toLowerCase() : undefined;
    }

    if (
      typeof value === 'object' &&
      value !== null &&
      '$oid' in value &&
      typeof value.$oid === 'string'
    ) {
      return /^[a-fA-F0-9]{24}$/.test(value.$oid)
        ? value.$oid.toLowerCase()
        : undefined;
    }

    return undefined;
  }

  private async ensureLockIndexes(): Promise<void> {
    const lockCollection = this.connection.collection<BroadcastLockDocument>(
      BROADCAST_LOCK_COLLECTION,
    );
    // TTL index สำหรับล้าง lock ที่หมดอายุอัตโนมัติ
    await lockCollection.createIndex(
      { expiresAt: 1 },
      { expireAfterSeconds: 0 },
    );
  }

  private startLockRenewLoop(): void {
    this.lockRenewTimer = setInterval(() => {
      void this.tryAcquireBroadcastLeadership();
    }, BROADCAST_LOCK_RENEW_MS);
  }

  private async tryAcquireBroadcastLeadership(): Promise<void> {
    const lockCollection = this.connection.collection<BroadcastLockDocument>(
      BROADCAST_LOCK_COLLECTION,
    );
    const now = new Date();
    const expiresAt = new Date(now.getTime() + BROADCAST_LOCK_TTL_MS);
    const wasLeader = this.hasBroadcastLeadership;

    try {
      // ต่ออายุ lock เดิมของตัวเอง หรือแย่ง lock ได้เมื่อ lock เก่าหมดอายุ
      const updateResult = await lockCollection.updateOne(
        {
          _id: BROADCAST_LOCK_ID,
          $or: [{ expiresAt: { $lte: now } }, { source: this.sourceId }],
        },
        {
          $set: {
            source: this.sourceId,
            expiresAt,
            updatedAt: now,
          },
          $setOnInsert: {
            createdAt: now,
          },
        },
        { upsert: true },
      );

      this.hasBroadcastLeadership =
        updateResult.modifiedCount > 0 || updateResult.upsertedCount > 0;
    } catch (error: unknown) {
      if (this.isDuplicateKeyError(error)) {
        this.hasBroadcastLeadership = false;
      } else {
        this.logger.error(
          `Failed to acquire broadcast leadership: ${this.toErrorMessage(error)}`,
        );
      }
    }

    if (!wasLeader && this.hasBroadcastLeadership) {
      this.logger.log(`Broadcast leader acquired (source=${this.sourceId})`);
    }

    if (wasLeader && !this.hasBroadcastLeadership) {
      this.logger.warn(`Broadcast leader lost (source=${this.sourceId})`);
    }
  }

  private isDuplicateKeyError(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === 11000
    );
  }

  private toErrorMessage(error: unknown): string {
    if (error instanceof Error) {
      return error.message;
    }

    return String(error);
  }
}

import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';

interface TsChangedPayload {
  id: string;
  ts: { $oid: string };
  source: string;
  channelId?: string;
  clientId?: string;
  deleted?: boolean;
}

@WebSocketGateway({
  cors: {
    origin: '*',
  },
})
export class RealtimeGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(RealtimeGateway.name);
  private static readonly channelIdRegex = /^0\d{9}$/;

  handleConnection(client: Socket): void {
    // อ่าน channel/client จาก query เพื่อแยกห้องตามผู้ใช้งาน
    const channelId = this.extractChannelId(client);
    const clientId = this.extractClientId(client);

    if (channelId) {
      // join ห้องตาม channel เพื่อให้ broadcast แบบเจาะจงห้อง
      void client.join(channelId);
      this.logger.log(
        `Client connected: ${client.id} channel=${channelId} clientId=${clientId ?? 'unknown'}`,
      );
      return;
    }

    this.logger.log(`Client connected: ${client.id}`);
  }

  handleDisconnect(client: Socket): void {
    this.logger.log(`Client disconnected: ${client.id}`);
  }

  broadcastTsChanged(payload: TsChangedPayload): void {
    if (payload.channelId) {
      // ส่ง event เฉพาะสมาชิกในห้อง channel เดียวกัน
      this.logger.debug(
        `Emitting ts_changed to room ${payload.channelId} itemId=${payload.id}`,
      );
      this.server.to(payload.channelId).emit('ts_changed', payload);
      return;
    }

    this.logger.warn(
      `Skipped ts_changed broadcast without channelId (itemId=${payload.id})`,
    );
  }

  private extractChannelId(client: Socket): string | undefined {
    const rawValue = client.handshake.query?.channelId;
    let channelId: string | undefined;

    if (typeof rawValue === 'string') {
      channelId = rawValue;
    } else if (Array.isArray(rawValue)) {
      channelId = rawValue[0];
    }

    if (!channelId) {
      return undefined;
    }

    const trimmed = channelId.trim();
    if (!RealtimeGateway.channelIdRegex.test(trimmed)) {
      // invalid channel จะไม่ join room และไม่กระทบห้องอื่น
      this.logger.warn(
        `Client ${client.id} sent invalid channelId, using global stream`,
      );
      return undefined;
    }

    return trimmed;
  }

  private extractClientId(client: Socket): string | undefined {
    const rawValue = client.handshake.query?.clientId;
    if (typeof rawValue === 'string') {
      const trimmed = rawValue.trim();
      return trimmed || undefined;
    }

    if (Array.isArray(rawValue)) {
      const first = rawValue[0];
      if (typeof first === 'string') {
        const trimmed = first.trim();
        return trimmed || undefined;
      }
    }

    return undefined;
  }
}

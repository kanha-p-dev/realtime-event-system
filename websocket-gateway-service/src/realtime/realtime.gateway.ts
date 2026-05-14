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
  private static readonly channelIdRegex = /^[a-zA-Z0-9_-]{6,120}$/;

  handleConnection(client: Socket): void {
    const channelId = this.extractChannelId(client);

    if (channelId) {
      void client.join(channelId);
      this.logger.log(`Client connected: ${client.id} channel=${channelId}`);
      return;
    }

    this.logger.log(`Client connected: ${client.id}`);
  }

  handleDisconnect(client: Socket): void {
    this.logger.log(`Client disconnected: ${client.id}`);
  }

  broadcastTsChanged(payload: TsChangedPayload): void {
    if (payload.channelId) {
      this.server.to(payload.channelId).emit('ts_changed', payload);
      return;
    }

    this.server.emit('ts_changed', payload);
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
      this.logger.warn(
        `Client ${client.id} sent invalid channelId, using global stream`,
      );
      return undefined;
    }

    return trimmed;
  }
}

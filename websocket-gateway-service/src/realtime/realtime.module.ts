import { Module } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';
import { ChangeStreamService } from './change-stream.service';

@Module({
  providers: [RealtimeGateway, ChangeStreamService],
})
export class RealtimeModule {}

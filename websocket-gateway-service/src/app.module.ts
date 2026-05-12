import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { RealtimeModule } from './realtime/realtime.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    MongooseModule.forRoot(
      process.env.MONGODB_URI ??
        'mongodb+srv://<username>:<password>@cluster0.rtyjoz0.mongodb.net/realtime_event_system?retryWrites=true&w=majority&appName=Cluster0',
    ),
    RealtimeModule,
  ],
})
export class AppModule {}

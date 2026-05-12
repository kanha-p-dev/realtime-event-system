import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { MongooseModule } from '@nestjs/mongoose';
import { ItemsModule } from './items/items.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    MongooseModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const mongoUri = configService.get<string>('MONGODB_URI');
        const mongoDbName =
          configService.get<string>('MONGODB_DB_NAME') ??
          'realtime_event_system';

        if (!mongoUri) {
          throw new Error('MONGODB_URI is required');
        }

        return {
          uri: mongoUri,
          dbName: mongoDbName,
        };
      },
    }),
    ItemsModule,
  ],
})
export class AppModule {}

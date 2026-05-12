# Realtime Event System (Microservice, Atlas Only)

End-to-end demo for this architecture:

- Backend Service (NestJS API): write/update MongoDB Atlas
- WebSocket Gateway Service (NestJS + Socket.IO): listens to MongoDB Change Stream and emits `ts_changed`
- Frontend (Flutter): listens to `ts_changed` and refetches list

## Project structure

- `backend-service`: REST API service
- `websocket-gateway-service`: WebSocket gateway service
- `frontend_flutter`: Flutter app

## Prerequisites

- MongoDB Atlas (replica set cluster)
- Node.js 20+
- Flutter 3+

## MongoDB Atlas setup

1. Create database name: `realtime_event_system`
2. Collection name: `items`
3. Add your current IP in Atlas Network Access
4. Create DB user with read/write permission for this database

The app uses this document shape in `items`:

```json
{
  "_id": "ObjectId",
  "name": "sensor-A",
  "ts": "2026-05-11T09:30:00.000Z",
  "createdAt": "2026-05-11T09:30:00.000Z",
  "updatedAt": "2026-05-11T09:30:00.000Z"
}
```

Notes:
- `_id`, `createdAt`, `updatedAt` are generated automatically.
- Collection will be auto-created on first insert.

## 1) Configure Backend API Service

```bash
cd backend-service
cp .env.example .env
```

Set `MONGODB_URI` in `.env`:

```env
PORT=3000
MONGODB_URI=mongodb+srv://<username>:<password>@cluster0.rtyjoz0.mongodb.net/realtime_event_system?retryWrites=true&w=majority&appName=Cluster0
```

Start service:

```bash
npm run start:dev
```

Service URL: `http://localhost:3000`

## 2) Configure WebSocket Gateway Service

Open another terminal:

```bash
cd websocket-gateway-service
cp .env.example .env
```

Set `MONGODB_URI` in `.env` to the same Atlas URI as backend.

Start service:

```bash
npm run start:dev
```

Gateway URL: `http://localhost:3001`

## 3) Start Flutter App

Open another terminal:

```bash
cd frontend_flutter
flutter run --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=SOCKET_BASE_URL=http://localhost:3001
```

If running Android emulator, use `10.0.2.2` instead of `localhost`:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=SOCKET_BASE_URL=http://10.0.2.2:3001
```

## API endpoints

- `POST /items`
  - body: `{ "name": "sensor-A" }`
- `GET /items`
- `PATCH /items/:id/ts`

## Realtime event payload

Socket event: `ts_changed`

```json
{
  "id": "6820e4f3b7...",
  "ts": "2026-05-11T08:30:15.123Z"
}
```

## How to test end-to-end

1. Create item in Flutter app.
2. Click `Update ts` on any item.
3. API updates MongoDB Atlas.
4. Gateway receives MongoDB Change Stream event and emits `ts_changed`.
5. Flutter receives event and automatically refreshes list.

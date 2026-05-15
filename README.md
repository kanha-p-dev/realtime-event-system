# Realtime Event System

เดโมระบบแจ้งเตือนแบบเรียลไทม์ที่แยกตามช่องทาง (Channel)

ระบบประกอบด้วย 3 บริการหลัก:
- Backend Service (NestJS REST API): จัดการ CRUD และตรวจสอบ channel
- WebSocket Gateway Service (NestJS + Socket.IO): รับ MongoDB Change Stream แล้วส่ง event แบบ realtime
- Flutter Frontend: หน้าจอผู้ใช้แบบ realtime และแยกการแจ้งเตือนตาม channel

## ความสามารถหลัก

- แยกข้อมูล/แจ้งเตือนตาม channel ด้วยเบอร์โทรไทยรูปแบบ 0XXXXXXXXX
- รองรับการระบุอุปกรณ์ด้วย x-client-id
- ลบแบบ Soft delete (เก็บ deletedAt)
- ส่ง websocket แบบ room ตาม channelId
- ข้อความแจ้งเตือนแยกได้ว่าเป็นเครื่องตัวเองหรืออีกเครื่อง
- UI แสดงสถานะ Backend และ Socket แยกกัน

## โครงสร้างโปรเจกต์

- backend-service
- websocket-gateway-service
- frontend_flutter
- docker-compose.yml

## สิ่งที่ต้องมี

- Docker + Docker Compose (แนะนำ)
- หรือ Node.js 20+ และ Flutter 3+
- MongoDB Atlas แบบ replica set (จำเป็นสำหรับ Change Stream)

## เริ่มต้นด้วย Docker

1. ตั้งค่า environment ที่ต้องใช้ (เช่น MONGODB_URI)
2. รันบริการทั้งหมด

```bash
docker compose up -d --build
```

3. ตรวจสอบสถานะ

```bash
docker compose ps
```

พอร์ตเริ่มต้น:
- Backend: http://localhost:3000
- Gateway: http://localhost:3001

## รัน Flutter

### iOS Simulator

```bash
cd frontend_flutter
flutter run --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=SOCKET_BASE_URL=http://localhost:3001
```

### Android Emulator

```bash
cd frontend_flutter
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=SOCKET_BASE_URL=http://10.0.2.2:3001
```

## สรุป REST API

ทุก endpoint ต้องส่ง x-channel-id (รูปแบบเบอร์ไทย)

- POST /items
  - headers: x-channel-id, x-client-id (ไม่บังคับ)
  - body: { "name": "ชื่อรายการ" }
- GET /items
  - headers: x-channel-id
- PATCH /items/:id/ts
  - headers: x-channel-id, x-client-id (ไม่บังคับ)
- DELETE /items/:id
  - headers: x-channel-id, x-client-id (ไม่บังคับ)

## WebSocket Event

Gateway จะส่ง event ชื่อ ts_changed ไปยัง room ตาม channelId

ตัวอย่าง payload:

```json
{
  "id": "6a06...",
  "ts": { "$oid": "6a06..." },
  "source": "pid-uuid",
  "channelId": "0812345678",
  "clientId": "device_...",
  "deleted": false
}
```

## เช็กลิสต์ทดสอบ

1. เปิด 2 เครื่อง
2. ตั้ง channel คนละเบอร์ เช่น
   - เครื่อง 1: 0812345678
   - เครื่อง 2: 0812345679
3. ทำ create/update/delete ที่เครื่อง 1 -> ต้องแจ้งเตือนเฉพาะ channel เครื่อง 1
4. ทำ create/update/delete ที่เครื่อง 2 -> ต้องแจ้งเตือนเฉพาะ channel เครื่อง 2
5. ตรวจสอบชิปสถานะ Backend และ Socket ในหน้า Flutter

## เอกสารเพิ่มเติม

- ARCHITECTURE_DIAGRAMS.md
- backend-service/README.md
- backend-service/ARCHITECTURE_DIAGRAMS.md
- frontend_flutter/README.md
- frontend_flutter/ARCHITECTURE_DIAGRAMS.md
- websocket-gateway-service/README.md
- websocket-gateway-service/ARCHITECTURE_DIAGRAMS.md

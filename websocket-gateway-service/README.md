# WebSocket Gateway Service

บริการ Socket.IO ที่รับ Change Stream จาก MongoDB แล้วส่ง event realtime ตาม room ของ channel

## หน้าที่ของบริการ

- รับ websocket connection จาก client
- อ่าน channelId และ clientId จาก handshake query
- join client เข้า room ตาม channelId
- watch Change Stream ของ collection items
- รวม event ที่ถี่ (coalesce) และหน่วงสั้น (debounce)
- ส่ง event จาก instance ที่เป็น leader เท่านั้น

## วิธีรัน

```bash
cd websocket-gateway-service
npm install
npm run start:dev
```

ค่าเริ่มต้น: http://localhost:3001

## Handshake query

- channelId (เบอร์ไทย 0XXXXXXXXX)
- clientId (ไม่บังคับ)

ถ้า channelId ถูกต้อง client จะถูก join เข้า room นั้น

## Event ที่ส่งออก

event: ts_changed

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

## พฤติกรรม Change Stream

- รองรับ operation: insert, update, replace, delete
- debounce 50ms
- coalesce ต่อ item id (เอาค่าล่าสุดในช่วงหน่วง)
- ใช้ lock collection: realtime_broadcast_locks เพื่อเลือก leader

## หมายเหตุ

- broadcast แบบเจาะ room ตาม channel เท่านั้น
- channelId ไม่ถูกต้องจะไม่ถูก join room
- เฉพาะ leader instance จะ flush event ไป websocket

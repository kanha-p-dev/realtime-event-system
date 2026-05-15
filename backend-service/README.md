# Backend Service

REST API สำหรับจัดการข้อมูลแบบแยก channel

## หน้าที่ของบริการ

- ตรวจสอบ x-channel-id (บังคับ)
- ตรวจสอบ x-client-id (ไม่บังคับ)
- CRUD แบบผูกกับ channel
- รองรับ soft delete
- บันทึกข้อมูลที่ใช้กับ realtime (lastUpdatedByChannel, lastUpdatedByClient)

## เทคโนโลยี

- NestJS
- Mongoose
- MongoDB Atlas

## วิธีรัน

```bash
cd backend-service
npm install
npm run start:dev
```

ค่าเริ่มต้น: http://localhost:3000

## Header ที่ใช้

- บังคับ: x-channel-id (0XXXXXXXXX)
- ไม่บังคับ: x-client-id ([a-zA-Z0-9:_-]{6,120})

## API

### POST /items
สร้างรายการใหม่ใน channel ปัจจุบัน

```json
{ "name": "Item A" }
```

### GET /items
ดึงรายการที่ยังไม่ถูกลบใน channel ปัจจุบัน

### PATCH /items/:id/ts
อัปเดต ts เป็น ObjectId ใหม่ใน channel ปัจจุบัน

### DELETE /items/:id
ลบแบบ soft delete (ตั้ง deletedAt) ใน channel ปัจจุบัน

## ฟิลด์ข้อมูลสำคัญ

- name
- ts
- ownerChannelId
- lastUpdatedByChannel
- lastUpdatedByClient
- deletedAt
- createdAt, updatedAt

## หมายเหตุ

- ไม่มีหรือส่ง x-channel-id ไม่ถูกต้อง -> 400
- id ไม่ถูกต้อง หรือไม่พบข้อมูลใน channel -> 404
- ทุก operation ถูกจำกัดใน channel เดียวกัน

# Flutter Frontend

หน้าจอผู้ใช้แบบ realtime ที่ทำงานแยกตาม channel

## หน้าที่ของแอป

- ให้ผู้ใช้ตั้งค่า channel (เบอร์ไทย)
- เชื่อม websocket ด้วย {channelId, clientId}
- เรียก REST พร้อม header x-channel-id และ x-client-id
- แสดง notification แบบ realtime
- แสดงสถานะ Backend และ Socket แยกกัน

## วิธีรัน

```bash
cd frontend_flutter
flutter pub get
```

### iOS simulator

```bash
flutter run --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=SOCKET_BASE_URL=http://localhost:3001
```

### Android emulator

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=SOCKET_BASE_URL=http://10.0.2.2:3001
```

## พฤติกรรมสำคัญ

- channel ต้องเป็นเบอร์ไทยรูปแบบ 0XXXXXXXXX
- ถ้าเปลี่ยน channel หรือ socket room ไม่ตรง จะ reconnect อัตโนมัติ
- ใช้ forceNew=true และ multiplex=false เพื่อลดปัญหา reuse connection เดิม
- create/update/delete ผ่าน API ก่อน แล้วรับ event จาก gateway

## การจัดการ event realtime

event: ts_changed

- deleted=true -> ลบรายการออกจาก list
- ถ้าไม่มี item ใน memory -> refetch
- ถ้ามี item อยู่ -> อัปเดต ts ใน memory
- ข้อความ noti แยกเครื่องตัวเอง/อีกเครื่องตาม clientId

## ส่วน UI

- การ์ดตั้งค่า channel
- ชิปสถานะ Backend
- ชิปสถานะ Socket
- ชิป channel ปัจจุบัน
- ส่วนเพิ่มรายการ
- รายการข้อมูลพร้อมปุ่ม update ts และ delete

## หมายเหตุ

- รหัสและ ts แสดงแบบเต็ม
- ตัวนับ notification เพิ่มทุกครั้งที่รับ event
- snackbar มีการกันข้อความซ้ำช่วงสั้นเพื่อลด spam

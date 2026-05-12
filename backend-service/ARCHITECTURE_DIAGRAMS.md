# Backend Service - สถาปัตยกรรมและแผนผังการทำงาน

## 📋 สารบัญ
1. [Sequence Diagram](#sequence-diagram)
2. [Flowchart](#flowchart)

---

## Sequence Diagram

### Backend Service - REST API Operations

```mermaid
sequenceDiagram
    participant ผู้ใช้ as ผู้ใช้<br/>(Frontend)
    participant API as Backend Service<br/>(NestJS)
    participant MongoDB as MongoDB Atlas

    ผู้ใช้->>API: HTTP POST /items<br/>(สร้าง Item)
    API->>API: ตรวจสอบข้อมูล<br/>(Validation)
    API->>MongoDB: บันทึกข้อมูล<br/>(Insert Document)
    MongoDB-->>API: ส่งคืน Document<br/>พร้อม _id
    API-->>ผู้ใช้: ส่งคืน 201 Created<br/>พร้อมข้อมูล Item

    ผู้ใช้->>API: HTTP GET /items
    API->>MongoDB: ดึงข้อมูลทั้งหมด
    MongoDB-->>API: ส่งคืน Item List
    API-->>ผู้ใช้: ส่งคืน 200 OK<br/>พร้อมรายการ

    ผู้ใช้->>API: HTTP PATCH /items/:id/ts<br/>(รีเฟรช ts)
    API->>MongoDB: อัปเดต ts ด้วย ObjectId ใหม่
    MongoDB-->>API: ส่งคืน Updated Document
    API-->>ผู้ใช้: ส่งคืน 200 OK<br/>พร้อมข้อมูลที่อัปเดต
```

**คำอธิบาย:**
- Backend Service เป็น NestJS API Server ที่ทำงานบน PORT 3000
- รับ HTTP Requests จาก Frontend สำหรับ 3 endpoints
- ตรวจสอบความถูกต้องของข้อมูลก่อนบันทึก (ValidationPipe)
- บันทึก/อ่าน/อัปเดต ts ข้อมูล ในคอลเลคชัน `items` ใน MongoDB Atlas
- ส่ง Response กลับไปยัง Frontend พร้อมข้อมูลหรือ Error Message

---

## Flowchart

### Backend Service - Request Processing Flow

```mermaid
flowchart TD
    A["🔧 Backend Service<br/>(NestJS API)<br/>PORT 3000"] --> B{"ได้รับคำขอ<br/>HTTP Request?"}
    
    B -->|POST /items| C["📝 Create Item<br/>ตรวจสอบข้อมูล<br/>Validation"]
    B -->|GET /items| D["📖 Read Items<br/>ดึงข้อมูลทั้งหมด"]
    B -->|PATCH /items/:id/ts| E["✏️ Refresh ts<br/>อัปเดต ts ด้วย ObjectId ใหม่"]
    
    C --> H{"ข้อมูล<br/>ถูกต้อง?"}
    H -->|ใช่| I["💾 MongoDB Insert<br/>บันทึกข้อมูลใหม่"]
    H -->|ไม่| J["❌ Error 400<br/>Invalid Request Body"]
    I --> K["✅ Response 201<br/>Created"]
    J --> L["📤 Send Response"]
    
    D --> M["🔍 MongoDB find()<br/>sort updatedAt desc"]
    M --> N["✅ Response 200<br/>OK with Data"]
    
    E --> O["🔍 Validate ObjectId<br/>ค้นหา Item by ID"]
    O --> P{"Item<br/>มีอยู่?"}
    P -->|ใช่| Q["📝 Set ts = new ObjectId()<br/>findByIdAndUpdate"]
    P -->|ไม่| R["❌ Error 404<br/>Not Found"]
    Q --> S["✅ Response 200<br/>Updated Item"]
    R --> L
    
    K --> L
    N --> L
    S --> L
    L --> Z["📤 Send HTTP Response<br/>กลับไปยัง Client"]
```

**คำอธิบาย - Request Processing:**

1. **POST /items** (Create)
   - ตรวจสอบความถูกต้องของ Request Body (`name`: string, MaxLength 100)
   - ถ้าถูกต้อง → Insert ลงใน MongoDB (พร้อม `ts = new ObjectId()`) → Return 201 Created
   - ถ้าไม่ถูก → Return 400 Bad Request

2. **GET /items** (Read All)
   - Query ดึงทั้งหมด Items จาก MongoDB เรียงตาม `updatedAt` descending
   - Return 200 OK พร้อมข้อมูล

3. **PATCH /items/:id/ts** (Refresh ts)
   - ตรวจสอบว่า id เป็น ObjectId format
   - ค้นหา Item by ID
   - ถ้ามี → อัปเดต `ts = new ObjectId()` → Return 200 OK พร้อม Updated Item
   - ถ้าไม่มี (หรือ id ไม่ใช่ ObjectId format) → Return 404 Not Found

---

## 📊 API Endpoints

| Method | Endpoint | Status Code | คำอธิบาย |
|--------|----------|-------------|----------|
| POST | `/items` | 201 | สร้าง Item ใหม่ |
| GET | `/items` | 200 | ดึงรายการ Items ทั้งหมด |
| PATCH | `/items/:id/ts` | 200 | รีเฟรช ts ด้วย ObjectId ใหม่ |

---

## 📝 Request/Response Examples

### Create Item (POST /items)

**Request Body:**
```json
{
  "name": "sensor-A"
}
```

**Response (201 Created):**
```json
{
  "_id": "507f1f77bcf86cd799439011",
  "name": "sensor-A",
  "ts": "6820e4f3b7c2a1d3e5f60789",
  "createdAt": "2026-05-12T10:30:00.000Z",
  "updatedAt": "2026-05-12T10:30:00.000Z",
  "__v": 0
}
```

### Get All Items (GET /items)

**Response (200 OK):**
```json
[
  {
    "_id": "507f1f77bcf86cd799439011",
    "name": "sensor-A",
    "ts": "6820e4f3b7c2a1d3e5f60789",
    "createdAt": "2026-05-12T10:30:00.000Z",
    "updatedAt": "2026-05-12T10:30:00.000Z"
  },
  {
    "_id": "507f1f77bcf86cd799439012",
    "name": "sensor-B",
    "ts": "6820e4f3b7c2a1d3e5f6078a",
    "createdAt": "2026-05-12T10:35:00.000Z",
    "updatedAt": "2026-05-12T10:35:00.000Z"
  }
]
```

### Refresh ts (PATCH /items/:id/ts)

**Request:** No body required

**Response (200 OK):**
```json
{
  "_id": "507f1f77bcf86cd799439011",
  "name": "sensor-A",
  "ts": "6820e4f9a3b1c2d4e5f60790",
  "createdAt": "2026-05-12T10:30:00.000Z",
  "updatedAt": "2026-05-12T10:45:00.000Z"
}
```

---

## 🛠️ Setup & Configuration

### Prerequisites
- Node.js 20+
- MongoDB Atlas (Replica Set Cluster)
- npm or yarn

### Installation
```bash
cd backend-service
npm install
```

### Configuration (.env)
```env
PORT=3000
MONGODB_URI=mongodb+srv://<username>:<password>@cluster0.xxxx.mongodb.net/realtime_event_system?retryWrites=true&w=majority
```

### Running
```bash
# Development
npm run start:dev

# Production
npm run build
npm run start:prod
```

---

## 📦 Project Structure

```
backend-service/
├── src/
│   ├── app.module.ts          # Main module
│   ├── main.ts                # Entry point
│   ├── items/
│   │   ├── items.module.ts    # Items module
│   │   ├── items.controller.ts # API endpoints
│   │   ├── items.service.ts   # Business logic
│   │   ├── dto/               # Data Transfer Objects
│   │   └── schemas/           # Mongoose schemas
│   └── common/                # Shared utilities
├── test/                      # E2E tests
├── package.json
├── tsconfig.json
└── nest-cli.json
```

---

**หมายเหตุ:** Backend Service เป็นส่วนที่จัดการ 3 endpoints (`POST /items`, `GET /items`, `PATCH /items/:id/ts`) และเชื่อมต่อกับ MongoDB Atlas โดยตรง

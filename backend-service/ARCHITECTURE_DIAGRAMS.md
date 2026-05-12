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

    ผู้ใช้->>API: HTTP PATCH /items/:id<br/>(อัปเดต Item)
    API->>MongoDB: อัปเดต Document
    MongoDB-->>API: ส่งคืน Updated Document
    API-->>ผู้ใช้: ส่งคืน 200 OK<br/>พร้อมข้อมูลที่อัปเดต

    ผู้ใช้->>API: HTTP DELETE /items/:id
    API->>MongoDB: ลบ Document
    MongoDB-->>API: ยืนยันการลบ
    API-->>ผู้ใช้: ส่งคืน 200 OK
```

**คำอธิบาย:**
- Backend Service เป็น NestJS API Server ที่ทำงานบน PORT 3000
- รับ HTTP Requests จาก Frontend สำหรับ CRUD Operations
- ตรวจสอบความถูกต้องของข้อมูลก่อนบันทึก
- บันทึก/อ่าน/อัปเดต/ลบ ข้อมูล ในคอลเลคชัน `items` ใน MongoDB Atlas
- ส่ง Response กลับไปยัง Frontend พร้อมข้อมูลหรือ Error Message

---

## Flowchart

### Backend Service - Request Processing Flow

```mermaid
flowchart TD
    A["🔧 Backend Service<br/>(NestJS API)<br/>PORT 3000"] --> B{"ได้รับคำขอ<br/>HTTP Request?"}
    
    B -->|POST /items| C["📝 Create Item<br/>ตรวจสอบข้อมูล<br/>Validation"]
    B -->|GET /items| D["📖 Read Items<br/>ดึงข้อมูลทั้งหมด"]
    B -->|PATCH /items/:id| E["✏️ Update Item<br/>อัปเดตข้อมูล"]
    B -->|DELETE /items/:id| F["🗑️ Delete Item<br/>ลบข้อมูล"]
    B -->|GET /health| G["🏥 Health Check<br/>ตรวจสอบสถานะ"]
    
    C --> H{"ข้อมูล<br/>ถูกต้อง?"}
    H -->|ใช่| I["💾 MongoDB Insert<br/>บันทึกข้อมูลใหม่"]
    H -->|ไม่| J["❌ Error 400<br/>Invalid Request Body"]
    I --> K["✅ Response 201<br/>Created"]
    J --> L["📤 Send Response"]
    
    D --> M["🔍 MongoDB Query<br/>ดึง Item List"]
    M --> N["✅ Response 200<br/>OK with Data"]
    
    E --> O["🔍 Find Item by ID<br/>ค้นหา Item"]
    O --> P{"Item<br/>มีอยู่?"}
    P -->|ใช่| Q["📝 Update Document<br/>อัปเดตข้อมูล"]
    P -->|ไม่| R["❌ Error 404<br/>Not Found"]
    Q --> S["✅ Response 200<br/>Updated"]
    R --> L
    
    F --> T["🔍 Find Item by ID<br/>ค้นหา Item"]
    T --> U{"Item<br/>มีอยู่?"}
    U -->|ใช่| V["🗑️ Delete Document<br/>ลบข้อมูล"]
    U -->|ไม่| W["❌ Error 404<br/>Not Found"]
    V --> X["✅ Response 200<br/>Deleted"]
    W --> L
    
    G --> Y["✅ Response 200<br/>OK - Service is Running"]
    
    K --> L
    N --> L
    S --> L
    X --> L
    Y --> L
    L --> Z["📤 Send HTTP Response<br/>กลับไปยัง Client"]
```

**คำอธิบาย - Request Processing:**

1. **POST /items** (Create)
   - ตรวจสอบความถูกต้องของ Request Body
   - ถ้าถูกต้อง → Insert ลงใน MongoDB → Return 201 Created
   - ถ้าไม่ถูก → Return 400 Bad Request

2. **GET /items** (Read)
   - Query ดึงทั้งหมด Items จาก MongoDB
   - Return 200 OK พร้อมข้อมูล

3. **PATCH /items/:id** (Update)
   - ค้นหา Item by ID
   - ถ้ามี → Update Document → Return 200 OK
   - ถ้าไม่มี → Return 404 Not Found

4. **DELETE /items/:id** (Delete)
   - ค้นหา Item by ID
   - ถ้ามี → Delete Document → Return 200 OK
   - ถ้าไม่มี → Return 404 Not Found

5. **GET /health** (Health Check)
   - ตรวจสอบสถานะของ Service
   - Return 200 OK ถ้า Service ทำงานปกติ

---

## 📊 API Endpoints

| Method | Endpoint | ความสำคัญ | คำอธิบาย |
|--------|----------|-----------|----------|
| POST | `/items` | ⭐⭐⭐ | สร้าง Item ใหม่ |
| GET | `/items` | ⭐⭐⭐ | ดึงรายการ Items ทั้งหมด |
| GET | `/items/:id` | ⭐⭐ | ดึง Item เดี่ยว by ID |
| PATCH | `/items/:id` | ⭐⭐⭐ | อัปเดต Item |
| DELETE | `/items/:id` | ⭐⭐ | ลบ Item |
| GET | `/health` | ⭐ | ตรวจสอบสถานะ Service |

---

## 📝 Request/Response Examples

### Create Item (POST /items)

**Request:**
```json
{
  "name": "sensor-A",
  "description": "Temperature sensor in room A"
}
```

**Response (201 Created):**
```json
{
  "_id": "507f1f77bcf86cd799439011",
  "name": "sensor-A",
  "description": "Temperature sensor in room A",
  "createdAt": "2026-05-12T10:30:00.000Z",
  "updatedAt": "2026-05-12T10:30:00.000Z"
}
```

### Get All Items (GET /items)

**Response (200 OK):**
```json
[
  {
    "_id": "507f1f77bcf86cd799439011",
    "name": "sensor-A",
    "description": "Temperature sensor in room A",
    "createdAt": "2026-05-12T10:30:00.000Z",
    "updatedAt": "2026-05-12T10:30:00.000Z"
  },
  {
    "_id": "507f1f77bcf86cd799439012",
    "name": "sensor-B",
    "description": "Humidity sensor in room B",
    "createdAt": "2026-05-12T10:35:00.000Z",
    "updatedAt": "2026-05-12T10:35:00.000Z"
  }
]
```

### Update Item (PATCH /items/:id)

**Request:**
```json
{
  "name": "sensor-A",
  "description": "Updated temperature sensor"
}
```

**Response (200 OK):**
```json
{
  "_id": "507f1f77bcf86cd799439011",
  "name": "sensor-A",
  "description": "Updated temperature sensor",
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

**หมายเหตุ:** Backend Service เป็นส่วนที่จัดการ CRUD Operations และเชื่อมต่อกับ MongoDB Atlas โดยตรง

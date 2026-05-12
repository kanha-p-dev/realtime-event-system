# Flutter Frontend - สถาปัตยกรรมและแผนผังการทำงาน

## 📋 สารบัญ
1. [Sequence Diagram](#sequence-diagram)
2. [Flowchart](#flowchart)

---

## Sequence Diagram

### Flutter Frontend - User Interaction & Real-time Updates

```mermaid
sequenceDiagram
    participant User as 👤 ผู้ใช้
    participant UI as 📱 Flutter UI<br/>Items Screen
    participant API as 🔧 Backend API<br/>REST Client
    participant Socket as 🔌 WebSocket<br/>Socket.IO Client
    participant Backend as 🔧 Backend Service<br/>NestJS
    participant DB as 💾 MongoDB

    rect rgb(200, 220, 255)
        Note over UI,Socket: App Startup - เชื่อมต่อบริการต่าง ๆ
        UI->>API: ✅ Initialize REST Client
        UI->>Socket: ✅ Connect Socket.IO
        Socket-->>UI: Connected ✅
    end

    rect rgb(200, 255, 200)
        Note over UI: โหลดข้อมูล
        UI->>API: GET /items
        API->>Backend: Forward request
        Backend->>DB: Query all items
        DB-->>Backend: Return items
        Backend-->>API: Response with data
        API-->>UI: Display items in list
    end

    rect rgb(255, 240, 200)
        Note over User,UI: ผู้ใช้ทำการเพิ่ม Item
        User->>UI: 1️⃣ Tap "Add Item"
        UI->>UI: 2️⃣ Show dialog form
        User->>UI: 3️⃣ Fill name field
        User->>UI: 4️⃣ Tap "Submit"
    end

    rect rgb(200, 220, 255)
        Note over UI,Backend: ส่งข้อมูลใหม่
        UI->>API: 5️⃣ POST /items<br/>(name: "sensor-A")
        API->>Backend: Forward POST request
        Backend->>DB: INSERT new document
        DB-->>Backend: Return created document
        Backend-->>API: Response 201
        API-->>UI: 6️⃣ Success ✅
    end

    rect rgb(255, 200, 200)
        Note over Socket,DB: Real-time notification
        DB->>Socket: 7️⃣ Change Stream Event
        Socket->>UI: 8️⃣ Emit ts_changed
        UI-->>Socket: Acknowledged
    end

    rect rgb(200, 255, 200)
        Note over UI,Backend: Refetch data
        UI->>API: 9️⃣ GET /items
        API->>Backend: Query items
        Backend->>DB: Query all items
        DB-->>Backend: Return updated list
        Backend-->>API: Response with data
        API-->>UI: 🔄 Refresh list
        UI->>UI: 🔟 Update UI with<br/>new item
        UI-->>User: ✅ Item added!
    end
```

**คำอธิบาย:**
1. ผู้ใช้เปิด App → เชื่อมต่อ REST Client และ Socket.IO
2. โหลดข้อมูล Items จาก Backend
3. ผู้ใช้กด "Add Item" → เปิด Dialog Form
4. กรอกข้อมูล และ Submit
5. Flutter ส่ง POST /items ไปยัง Backend
6. Backend บันทึก ลง MongoDB
7. MongoDB Change Stream ส่ง Event ไปยัง Gateway
8. Gateway Emit `ts_changed` ไปยัง Flutter App
9. Flutter ได้รับการแจ้งเตือน และ GET /items เพื่อ Refetch
10. UI Update ด้วยข้อมูลล่าสุด

---

## Flowchart

### Flutter Frontend - User Interaction & Data Flow

```mermaid
flowchart TD
    A["📱 Flutter App<br/>Main Screen"] --> B["🚀 Initialize"]
    
    B --> C["📡 Create HTTP Client<br/>REST API Connection"]
    C --> D["🔌 Initialize Socket.IO<br/>WebSocket Connection"]
    
    D --> E{"Socket<br/>Connected?"}
    E -->|ไม่| F["❌ Retry Connection<br/>Exponential Backoff"]
    F --> E
    
    E -->|ใช่| G["✅ Connection Ready"]
    G --> H["👂 Subscribe to Events<br/>Listen to ts_changed"]
    
    H --> I["📖 Load Items List<br/>GET /items"]
    I --> J["🔍 Fetch from Backend"]
    J --> K["📊 Parse JSON Response"]
    K --> L["🎨 Build ListView<br/>Display items"]
    
    L --> M["👀 Show Items Screen<br/>to User"]
    
    M --> N{"User Action?"}
    
    N -->|👤 Scroll| O["📜 Scroll List<br/>View more items"]
    O --> M
    
    N -->|➕ Add Item| P["📝 Open Add Dialog"]
    P --> Q["✍️ User fills form<br/>name, description"]
    Q --> R["🎨 Validate Input<br/>Check empty fields"]
    
    R --> S{"Valid?"}
    S -->|ไม่| T["⚠️ Show Error<br/>Invalid input"]
    T --> Q
    
    S -->|ใช่| U["📤 POST /items<br/>Send to Backend"]
    U --> V["🔄 Loading State<br/>Show spinner"]
    V --> W{"Response<br/>Success?"}
    
    W -->|ไม่| X["❌ Show Error<br/>Failed to create"]
    X --> P
    
    W -->|ใช่| Y["✅ Item Created<br/>Close dialog"]
    Y --> Z["⏳ Wait for ts_changed<br/>Real-time notification"]
    
    Z --> AA{"Got<br/>Notification?"}
    AA -->|ไม่| AB["⏱️ Timeout - Manual Refetch<br/>GET /items"]
    AA -->|ใช่| AC["⚡ Automatic Refetch<br/>GET /items"]
    
    AB --> AD["🔄 Refetch Items<br/>from Backend"]
    AC --> AD
    
    AD --> AE["📊 Update ListView<br/>Show new item"]
    AE --> AF["✨ Notify User<br/>Item added!"]
    AF --> M
    
    N -->|✏️ Edit Item| AG["📝 Open Edit Dialog<br/>PATCH /items/:id"]
    AG --> AH["✍️ Modify item data"]
    AH --> AI["📤 Send PATCH request"]
    AI --> AJ["🔄 Wait for ts_changed"]
    AJ --> AD
    
    N -->|🗑️ Delete Item| AK["❓ Confirm delete<br/>Show confirmation"]
    AK --> AL{"User<br/>Confirm?"}
    
    AL -->|ไม่| M
    AL -->|ใช่| AM["📤 DELETE /items/:id"]
    AM --> AN["🔄 Wait for ts_changed"]
    AN --> AD
```

**คำอธิบาย - User Interaction Flow:**

1. **Initialization**
   - สร้าง HTTP Client สำหรับ REST API
   - Initialize Socket.IO เชื่อมต่อ WebSocket
   - Subscribe ไปยัง `ts_changed` Event

2. **Load Data**
   - ส่ง GET /items ไปยัง Backend
   - Parse JSON Response
   - Build ListView แสดงข้อมูล

3. **Add Item Flow**
   - ผู้ใช้กด "Add Item"
   - เปิด Dialog Form
   - ตรวจสอบความถูกต้องของข้อมูล
   - ส่ง POST /items ไปยัง Backend
   - รอการแจ้งเตือน `ts_changed`
   - Refetch ข้อมูลล่าสุด
   - Update UI

4. **Edit Item Flow**
   - เปิด Edit Dialog
   - แก้ไขข้อมูล
   - ส่ง PATCH /items/:id
   - รอการแจ้งเตือน
   - Refetch และ Update

5. **Delete Item Flow**
   - ผู้ใช้เลือก Delete
   - แสดง Confirmation Dialog
   - ส่ง DELETE /items/:id
   - รอการแจ้งเตือน
   - Refetch และ Update

---

## 🎨 Widget Architecture

### Main Widget Tree

```
MyApp
├── MaterialApp
│   └── ItemsScreen
│       ├── AppBar
│       │   ├── Title: "Items"
│       │   └── FloatingActionButton: Add
│       ├── Body: ItemsList
│       │   └── ListView.builder
│       │       └── ItemTile (for each item)
│       │           ├── ListTile
│       │           ├── Edit Button
│       │           └── Delete Button
│       └── BottomNavigationBar
│
├── Dialogs
│   ├── AddItemDialog
│   │   ├── TextField: name
│   │   ├── TextField: description
│   │   ├── Button: Cancel
│   │   └── Button: Submit
│   ├── EditItemDialog
│   │   └── Similar to AddItemDialog
│   └── ConfirmDialog
│       ├── Text: "Delete?"
│       ├── Button: Cancel
│       └── Button: Confirm
│
└── Services
    ├── ApiService
    │   ├── createItem()
    │   ├── getItems()
    │   ├── updateItem()
    │   └── deleteItem()
    └── WebSocketService
        ├── connect()
        ├── disconnect()
        ├── subscribe()
        └── onTsChanged()
```

---

## 🔧 Service Classes

### ApiService (HTTP Client)

```dart
class ApiService {
  final String baseUrl = 'http://localhost:3000';
  
  Future<Item> createItem(String name, String description)
  Future<List<Item>> getItems()
  Future<Item> updateItem(String id, String name, String description)
  Future<void> deleteItem(String id)
}
```

### WebSocketService (Socket.IO Client)

```dart
class WebSocketService {
  final String socketUrl = 'http://localhost:3001';
  
  Future<void> connect()
  Future<void> disconnect()
  void subscribeToTsChanged(Function callback)
  void unsubscribeFromTsChanged()
}
```

---

## 📱 Screens

### Items List Screen

| Element | Purpose |
|---------|---------|
| AppBar | Header พร้อม Title และ Add Button |
| ListView | แสดงรายการ Items |
| ItemTile | Card แสดง Item พร้อม Edit/Delete |
| FloatingActionButton | ปุ่มเพิ่ม Item ใหม่ |
| SnackBar | แสดง Success/Error Messages |

### Add/Edit Item Dialog

| Element | Purpose |
|---------|---------|
| TextField: Name | รับข้อมูล Name |
| TextField: Description | รับข้อมูล Description |
| Submit Button | ส่งข้อมูล |
| Cancel Button | ยกเลิก |
| Validation | ตรวจสอบความถูกต้อง |

---

## 🛠️ Setup & Configuration

### Prerequisites
- Flutter 3+
- Dart 3+
- iOS/Android development environment

### Installation
```bash
cd frontend_flutter
flutter pub get
```

### Configuration

**lib/config/constants.dart:**
```dart
class Config {
  static const String apiBaseUrl = 'http://localhost:3000';
  static const String socketBaseUrl = 'http://localhost:3001';
  static const int connectTimeout = 30000; // ms
  static const int receiveTimeout = 30000; // ms
}
```

### Running

**Android Emulator:**
```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 \
            --dart-define=SOCKET_BASE_URL=http://10.0.2.2:3001
```

**iOS Simulator:**
```bash
flutter run --dart-define=API_BASE_URL=http://localhost:3000 \
            --dart-define=SOCKET_BASE_URL=http://localhost:3001
```

**Web:**
```bash
flutter run -d web-server
```

---

## 📦 Project Structure

```
frontend_flutter/
├── lib/
│   ├── main.dart                    # Entry point
│   ├── config/
│   │   └── constants.dart          # Configuration
│   ├── models/
│   │   └── item.dart               # Item data model
│   ├── screens/
│   │   └── items_screen.dart       # Main screen
│   ├── widgets/
│   │   ├── item_tile.dart          # Item list tile
│   │   ├── add_item_dialog.dart    # Add dialog
│   │   └── dialogs.dart            # Other dialogs
│   ├── services/
│   │   ├── api_service.dart        # HTTP client
│   │   ├── websocket_service.dart  # Socket.IO client
│   │   └── item_service.dart       # Business logic
│   └── utils/
│       └── logger.dart             # Logging
├── test/
│   └── widget_test.dart            # Widget tests
├── pubspec.yaml                    # Dependencies
└── README.md
```

---

## 📦 Dependencies

**pubspec.yaml:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0                      # HTTP client
  socket_io_client: ^2.0.0          # Socket.IO client
  provider: ^6.0.0                  # State management
  json_serializable: ^6.0.0          # JSON serialization
  equatable: ^2.0.5                 # Value equality

dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.0                   # Mocking
```

---

## 🔄 State Management

### Using Provider Pattern

```dart
class ItemProvider extends ChangeNotifier {
  List<Item> items = [];
  bool isLoading = false;
  
  Future<void> loadItems() { ... }
  Future<void> createItem(Item item) { ... }
  Future<void> updateItem(Item item) { ... }
  Future<void> deleteItem(String id) { ... }
  
  void onTsChanged() {
    loadItems(); // Refetch when notified
  }
}
```

---

## ⚠️ Important Notes

✅ **HTTP Client Configuration**
- Use `10.0.2.2` instead of `localhost` for Android emulator
- iOS simulator can use `localhost`
- Web needs `http://localhost`

✅ **Socket.IO Connection**
- Automatic reconnection with exponential backoff
- Connection timeout: 30 seconds
- Keep-alive with ping/pong

✅ **Error Handling**
- Show user-friendly error messages
- Log errors for debugging
- Retry failed requests with exponential backoff

✅ **Real-time Updates**
- Listen to `ts_changed` event continuously
- Refetch data when notification received
- Debounce rapid updates (max 1 refetch per second)

---

**หมายเหตุ:** Flutter Frontend เป็น UI/UX Layer ที่ให้ผู้ใช้โต้ตอบกับระบบ และแสดงข้อมูลแบบ Real-time

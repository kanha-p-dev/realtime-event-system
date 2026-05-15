# สถาปัตยกรรมระบบ Realtime Event System

เอกสารนี้อธิบายภาพรวม End-to-End ของ Frontend, Backend, Gateway และ MongoDB

## Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant FE as Flutter Frontend
    participant BE as Backend Service
    participant DB as MongoDB Atlas
    participant GW as WebSocket Gateway

    Note over FE,GW: Startup
    FE->>FE: Set channelId (Thai phone format)
    FE->>GW: Connect socket with query {channelId, clientId}
    GW->>GW: Join room by channelId
    FE->>BE: GET /items + x-channel-id
    BE->>DB: Query by ownerChannelId and not deleted
    DB-->>BE: Item list
    BE-->>FE: 200 + list

    Note over U,FE: User actions
    U->>FE: create / update / delete
    FE->>BE: REST + x-channel-id + x-client-id
    BE->>DB: Persist lastUpdatedByChannel and lastUpdatedByClient
    DB-->>BE: Updated document
    BE-->>FE: Success response

    Note over DB,GW: Change Stream
    DB->>GW: insert/update/replace/delete
    GW->>GW: Debounce + coalesce + leadership check
    GW-->>FE: ts_changed to room(channelId)
    FE->>FE: Update in-memory or refetch
    FE->>FE: Increase notification counter
```

## Flowchart

```mermaid
flowchart TD
    A[Flutter UI] --> B[Set channelId]
    B --> C[Connect socket to room by channelId]
    C --> D[Load items with x-channel-id]

    D --> E{User action}
    E -->|Create| F[POST /items]
    E -->|Update ts| G[PATCH /items/:id/ts]
    E -->|Delete| H[DELETE /items/:id]

    F --> I[Backend validates channel/client headers]
    G --> I
    H --> I

    I --> J[Write MongoDB with lastUpdatedByChannel/client]
    J --> K[Change Stream event]
    K --> L[Gateway emits ts_changed to room(channelId)]
    L --> M[Frontend receives event]
    M --> N{Item exists in memory?}
    N -->|Yes| O[Update in-place]
    N -->|No| P[Refetch GET /items]
    O --> Q[Update UI + notifications]
    P --> Q
```

## แนวคิดหลักของระบบ

- แยก channel ด้วย x-channel-id และ Socket room ตาม channelId
- channel รับเฉพาะเบอร์ไทยรูปแบบ 0XXXXXXXXX
- ระบุที่มาอุปกรณ์ด้วย x-client-id / clientId
- การลบเป็น soft delete และส่ง event deleted=true
- กรณีหลาย gateway จะมีเฉพาะ leader ที่ส่ง broadcast

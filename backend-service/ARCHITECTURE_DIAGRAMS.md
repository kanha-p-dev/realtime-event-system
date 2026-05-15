# สถาปัตยกรรม Backend Service

## Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    participant FE as Frontend
    participant API as Backend API
    participant DB as MongoDB Atlas

    FE->>API: REST + x-channel-id (+ x-client-id)
    API->>API: Validate headers and input

    alt POST /items
        API->>DB: Insert with ownerChannelId, lastUpdatedByChannel, lastUpdatedByClient
        DB-->>API: created item
        API-->>FE: 201
    else GET /items
        API->>DB: Find by ownerChannelId and not deleted
        DB-->>API: list
        API-->>FE: 200
    else PATCH /items/:id/ts
        API->>DB: findOneAndUpdate in channel and set new ts
        DB-->>API: updated item
        API-->>FE: 200
    else DELETE /items/:id
        API->>DB: findOneAndUpdate in channel and set deletedAt + new ts
        DB-->>API: deleted item
        API-->>FE: 200
    end
```

## Flowchart

```mermaid
flowchart TD
    A[Request arrives] --> B[Validate x-channel-id]
    B --> C{Select endpoint}

    C -->|POST /items| D[Insert document]
    C -->|GET /items| E[Find by channel + not deleted]
    C -->|PATCH /items/:id/ts| F[Update ts in channel]
    C -->|DELETE /items/:id| G[Soft delete in channel]

    D --> H[Send response]
    E --> H
    F --> H
    G --> H
```

## กติกา validation

- x-channel-id: ^0\\d{9}$
- x-client-id (ไม่บังคับ): ^[a-zA-Z0-9:_-]{6,120}$

## การรับประกันระดับข้อมูล

- ผู้ใช้เห็น/แก้ไขได้เฉพาะข้อมูลใน ownerChannelId เดียวกัน
- รายการที่ถูกลบ (deletedAt มีค่า) จะไม่ถูกส่งใน GET /items

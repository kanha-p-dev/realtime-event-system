# สถาปัตยกรรม Flutter Frontend

## Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant FE as Flutter UI
    participant API as Backend API
    participant GW as WebSocket Gateway

    U->>FE: Set channel (Thai phone format)
    FE->>FE: Validate and normalize
    FE->>GW: Connect socket with query {channelId, clientId}
    GW-->>FE: connected

    FE->>API: GET /items + x-channel-id
    API-->>FE: list
    FE->>FE: Render list

    U->>FE: create / update / delete
    FE->>API: REST + x-channel-id + x-client-id
    API-->>FE: success

    GW-->>FE: ts_changed {id, ts, channelId, clientId, deleted}
    FE->>FE: Check active channel
    alt deleted
        FE->>FE: Remove item from list
    else item exists
        FE->>FE: Update ts in memory
    else item missing
        FE->>API: GET /items (refetch)
        API-->>FE: latest list
    end
    FE->>FE: Update notification count and message
```

## Flowchart

```mermaid
flowchart TD
    A[User enters channel] --> B[Validate Thai phone format]
    B --> C[apply channel]
    C --> D[Reconnect socket if needed]
    D --> E[fetch items]

    E --> F{User action}
    F -->|Create| G[POST /items]
    F -->|Update ts| H[PATCH /items/:id/ts]
    F -->|Delete| I[DELETE /items/:id]

    G --> J[Receive response]
    H --> J
    I --> J

    J --> K[Wait for ts_changed]
    K --> L{Item exists in memory?}
    L -->|Yes| M[Update in-memory]
    L -->|No| N[Refetch GET /items]
    M --> O[Update UI + notification]
    N --> O
```

## สถานะสำคัญในแอป

- _channelId: channel ปัจจุบัน
- _socketChannelId: room ที่ socket ต่ออยู่จริง
- _clientId: id เครื่อง/แอปปัจจุบัน
- _isBackendConnected: สถานะ backend จากผล API
- _notificationCount: ตัวนับการแจ้งเตือน

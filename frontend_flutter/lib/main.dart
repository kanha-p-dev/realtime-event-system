import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);
const String socketBaseUrl = String.fromEnvironment(
  'SOCKET_BASE_URL',
  defaultValue: 'http://localhost:3001',
);
const Duration apiTimeout = Duration(seconds: 8);
const Duration duplicateNotificationCooldown = Duration(seconds: 5);

void main() {
  debugPrint('[DEBUG] Flutter app started');
  runApp(const RealtimeApp());
}

class RealtimeApp extends StatelessWidget {
  const RealtimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'เดโมเหตุการณ์เรียลไทม์',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const RealtimeHomePage(),
    );
  }
}

class ItemRecord {
  ItemRecord({required this.id, required this.name, required this.ts});

  final String id;
  final String name;
  final String ts;

  factory ItemRecord.fromJson(Map<String, dynamic> json) {
    final String idValue = json['_id'] as String;
    return ItemRecord(
      id: idValue,
      name: json['name'] as String,
      ts: _parseTsObjectId(json['ts'], idValue),
    );
  }

  static String? tryParseTsObjectId(dynamic rawTs) {
    if (rawTs is String && _isObjectId(rawTs)) {
      return rawTs;
    }

    if (rawTs is Map<String, dynamic>) {
      final dynamic oid = rawTs['\$oid'];
      if (oid is String && _isObjectId(oid)) {
        return oid;
      }
    }

    return null;
  }

  static String _parseTsObjectId(dynamic rawTs, String fallbackId) {
    // Supports ObjectId-backed ts values while keeping compatibility with legacy shapes.
    return tryParseTsObjectId(rawTs) ?? fallbackId;
  }

  static bool _isObjectId(String value) {
    final RegExp objectIdRegex = RegExp(r'^[a-fA-F0-9]{24}$');
    return objectIdRegex.hasMatch(value);
  }
}

class RealtimeHomePage extends StatefulWidget {
  const RealtimeHomePage({super.key});

  @override
  State<RealtimeHomePage> createState() => _RealtimeHomePageState();
}

class _RealtimeHomePageState extends State<RealtimeHomePage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneChannelController = TextEditingController(
    text: '0812345678',
  );
  List<ItemRecord> _items = <ItemRecord>[];
  final Set<String> _updatingItemIds = <String>{};
  final Set<String> _deletingItemIds = <String>{};
  bool _isLoading = false;
  String? _error;
  int _notificationCount = 0;
  String _lastNotification = 'ยังไม่มีการแจ้งเตือน';
  String? _lastNotificationMessage;
  DateTime? _lastNotificationAt;
  io.Socket? _socket;
  String? _socketChannelId;
  bool? _isBackendConnected;
  String? _channelId;
  final String _clientId = _buildClientId();
  int _latestFetchRequestId = 0;

  void _logRealtime(String message) {
    debugPrint('[realtime] $message');
  }

  void _setBackendConnection(bool connected) {
    if (!mounted || _isBackendConnected == connected) {
      return;
    }

    setState(() {
      _isBackendConnected = connected;
    });
  }

  static String _buildClientId() {
    final int now = DateTime.now().microsecondsSinceEpoch;
    final int rand = Random().nextInt(0x7fffffff);
    return 'device_${now.toRadixString(16)}_${rand.toRadixString(16)}';
  }

  String? _normalizeThaiPhoneChannel(String input) {
    final String compact = input.replaceAll(RegExp(r'[\s-]'), '');

    if (RegExp(r'^0\d{9}$').hasMatch(compact)) {
      return compact;
    }

    if (RegExp(r'^(\+66|66)\d{9}$').hasMatch(compact)) {
      final String localDigits = compact.startsWith('+66')
          ? compact.substring(3)
          : compact.substring(2);
      return '0$localDigits';
    }

    return null;
  }

  String? _requireChannelId() {
    final String? channelId = _channelId;
    if (channelId != null) {
      return channelId;
    }

    _setInlineError('กรุณาตั้งค่าเบอร์โทรช่องทางก่อนใช้งาน');
    return null;
  }

  Future<String?> _ensureActiveChannelForAction() async {
    final String? normalized = _normalizeThaiPhoneChannel(
      _phoneChannelController.text,
    );

    if (normalized == null) {
      _setInlineError('รูปแบบเบอร์โทรไม่ถูกต้อง (เช่น 0812345678)');
      return null;
    }

    final bool isSocketConnected = _socket?.connected ?? false;
    final bool socketMatchesChannel = _socketChannelId == normalized;
    if (_channelId != normalized ||
        !isSocketConnected ||
        !socketMatchesChannel) {
      _logRealtime(
        'ensure_channel_sync fromInput=$normalized current=$_channelId socketConnected=$isSocketConnected socketChannel=$_socketChannelId',
      );
      await _applyPhoneChannel();
    }

    return _requireChannelId();
  }

  Future<void> _applyPhoneChannel() async {
    final String? normalized = _normalizeThaiPhoneChannel(
      _phoneChannelController.text,
    );

    if (normalized == null) {
      _setInlineError('รูปแบบเบอร์โทรไม่ถูกต้อง (เช่น 0812345678)');
      return;
    }

    final bool channelChanged = _channelId != normalized;
    _channelId = normalized;
    _logRealtime('apply_channel channelId=$normalized changed=$channelChanged');

    if (!channelChanged) {
      _setInlineError('');

      // If same channel is applied again, ensure socket is connected.
      // This recovers realtime notifications after gateway/app restarts.
      final bool isSocketConnected = _socket?.connected ?? false;
      final bool socketMatchesChannel = _socketChannelId == normalized;
      if (!isSocketConnected || !socketMatchesChannel) {
        _logRealtime(
          'socket_reconnect_on_same_channel connected=$isSocketConnected socketChannel=$_socketChannelId expected=$normalized',
        );
        _socket?.dispose();
        _socket = null;
        _socketChannelId = null;
        _connectSocket();
      }
      return;
    }

    _socket?.dispose();
    _socket = null;
    _socketChannelId = null;

    if (!mounted) {
      return;
    }

    setState(() {
      _items = <ItemRecord>[];
      _notificationCount = 0;
      _lastNotification = 'ยังไม่มีการแจ้งเตือน';
      _error = null;
    });

    await _fetchItems();
    _connectSocket();
  }

  String _friendlyErrorMessage(
    Object error, {
    required String fallbackMessage,
  }) {
    if (error is TimeoutException) {
      return 'การเชื่อมต่อหมดเวลา กรุณาตรวจสอบว่า backend/server ทำงานอยู่';
    }

    final String rawError = error.toString();
    if (rawError.contains('SocketException') ||
        rawError.contains('Failed host lookup') ||
        rawError.contains('Connection refused')) {
      return 'ไม่สามารถเชื่อมต่อ backend ได้ กรุณาตรวจสอบว่า API ทำงานอยู่';
    }

    if (rawError.contains('ClientException')) {
      return 'คำขอเครือข่ายล้มเหลว กรุณาตรวจสอบ API endpoint และเครือข่าย';
    }

    return '$fallbackMessage ($rawError)';
  }

  void _setInlineError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _error = message;
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_applyPhoneChannel());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneChannelController.dispose();
    _socket?.dispose();
    _socket = null;
    _socketChannelId = null;
    super.dispose();
  }

  Future<void> _fetchItems() async {
    final String? channelId = _requireChannelId();
    if (channelId == null) {
      return;
    }

    final int requestId = ++_latestFetchRequestId;
    bool backendResponded = false;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final Uri uri = Uri.parse('$apiBaseUrl/items');
      final http.Response response = await http
          .get(uri, headers: <String, String>{'x-channel-id': channelId})
          .timeout(apiTimeout);
      backendResponded = true;
      _setBackendConnection(true);

      if (response.statusCode != 200) {
        throw Exception('โหลดรายการไม่สำเร็จ');
      }

      final List<dynamic> decoded = jsonDecode(response.body) as List<dynamic>;
      final List<ItemRecord> loadedItems = decoded
          .map(
            (dynamic item) => ItemRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      if (!mounted) {
        return;
      }

      if (_channelId != channelId || requestId != _latestFetchRequestId) {
        return;
      }

      setState(() {
        _items = loadedItems;
      });
    } catch (error) {
      if (!backendResponded) {
        _setBackendConnection(false);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _error = _friendlyErrorMessage(
          error,
          fallbackMessage: 'โหลดรายการไม่สำเร็จ',
        );
      });
    } finally {
      if (mounted) {
        if (_channelId != channelId || requestId != _latestFetchRequestId) {
          return;
        }

        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createItem() async {
    final String trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) {
      return;
    }

    bool backendResponded = false;

    try {
      _setInlineError('');
      final String? channelId = await _ensureActiveChannelForAction();
      if (channelId == null) {
        return;
      }

      final Uri uri = Uri.parse('$apiBaseUrl/items');
      final http.Response response = await http
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'x-channel-id': channelId,
              'x-client-id': _clientId,
            },
            body: jsonEncode(<String, String>{'name': trimmedName}),
          )
          .timeout(apiTimeout);
      backendResponded = true;
      _setBackendConnection(true);

      if (response.statusCode != 201 && response.statusCode != 200) {
        throw Exception('สร้างรายการไม่สำเร็จ (สถานะ: ${response.statusCode})');
      }

      // Parse response and add item to list immediately
      final Map<String, dynamic> decoded =
          jsonDecode(response.body) as Map<String, dynamic>;
      final ItemRecord newItem = ItemRecord.fromJson(decoded);

      if (!mounted) {
        return;
      }

      // Add new item to list immediately and mark it locally so we don't duplicate notify
      setState(() {
        _items.insert(0, newItem);
      });

      _nameController.clear();
    } catch (error) {
      if (!backendResponded) {
        _setBackendConnection(false);
      }

      final String message = _friendlyErrorMessage(
        error,
        fallbackMessage: 'ไม่สามารถสร้างรายการได้',
      );
      _setInlineError(message);
    }
  }

  Future<void> _refreshTs(String id) async {
    if (_updatingItemIds.contains(id)) {
      return;
    }

    final String? channelId = await _ensureActiveChannelForAction();
    if (channelId == null) {
      return;
    }

    final ItemRecord? currentItem = _findItemById(id);

    setState(() {
      _updatingItemIds.add(id);
    });

    bool backendResponded = false;

    try {
      final Uri uri = Uri.parse('$apiBaseUrl/items/$id/ts');
      final http.Response response = await http
          .patch(
            uri,
            headers: <String, String>{
              'x-channel-id': channelId,
              'x-client-id': _clientId,
            },
          )
          .timeout(apiTimeout);
      backendResponded = true;
      _setBackendConnection(true);

      if (response.statusCode != 200) {
        throw Exception('อัปเดต ts ไม่สำเร็จ (สถานะ: ${response.statusCode})');
      }

      final Map<String, dynamic> decoded =
          jsonDecode(response.body) as Map<String, dynamic>;
      final ItemRecord updatedItem = ItemRecord.fromJson(decoded);
      _applyItemUpdate(updatedItem);

      // If ts appears unchanged, re-fetch from API to resolve eventual consistency/race cases.
      if (currentItem != null && currentItem.ts == updatedItem.ts) {
        await _fetchItems();
      }
    } catch (error) {
      if (!backendResponded) {
        _setBackendConnection(false);
      }

      final String message = _friendlyErrorMessage(
        error,
        fallbackMessage: 'ไม่สามารถอัปเดต ts ได้',
      );
      _setInlineError(message);
    } finally {
      if (mounted) {
        setState(() {
          _updatingItemIds.remove(id);
        });
      }
    }
  }

  Future<void> _deleteItem(String id) async {
    if (_deletingItemIds.contains(id)) {
      return;
    }

    final String? channelId = await _ensureActiveChannelForAction();
    if (channelId == null) {
      return;
    }

    setState(() {
      _deletingItemIds.add(id);
    });

    bool backendResponded = false;

    try {
      final Uri uri = Uri.parse('$apiBaseUrl/items/$id');
      final http.Response response = await http
          .delete(
            uri,
            headers: <String, String>{
              'x-channel-id': channelId,
              'x-client-id': _clientId,
            },
          )
          .timeout(apiTimeout);
      backendResponded = true;
      _setBackendConnection(true);

      if (response.statusCode != 200) {
        throw Exception('ลบรายการไม่สำเร็จ (สถานะ: ${response.statusCode})');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _items = _items.where((ItemRecord item) => item.id != id).toList();
      });
    } catch (error) {
      if (!backendResponded) {
        _setBackendConnection(false);
      }

      final String message = _friendlyErrorMessage(
        error,
        fallbackMessage: 'ไม่สามารถลบรายการได้',
      );
      _setInlineError(message);
    } finally {
      if (mounted) {
        setState(() {
          _deletingItemIds.remove(id);
        });
      }
    }
  }

  Future<void> _confirmDeleteItem(ItemRecord item) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ยืนยันการลบ'),
          content: Text('ต้องการลบ "${item.name}" ใช่หรือไม่?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ลบ'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteItem(item.id);
    }
  }

  ItemRecord? _findItemById(String id) {
    for (final ItemRecord item in _items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  void _applyItemUpdate(ItemRecord updatedItem) {
    if (!mounted) {
      return;
    }

    setState(() {
      _items = _items.map((ItemRecord item) {
        if (item.id == updatedItem.id) {
          return updatedItem;
        }
        return item;
      }).toList();
    });
  }

  void _notifyUser(String message, {bool showSnackBar = true}) {
    if (!mounted) {
      debugPrint('[DEBUG] [NOTI] Widget not mounted, skipping notification');
      return;
    }

    final DateTime now = DateTime.now();
    final bool isDuplicate =
        _lastNotificationMessage == message &&
        _lastNotificationAt != null &&
        now.difference(_lastNotificationAt!) < duplicateNotificationCooldown;

    debugPrint(
      '[DEBUG] [NOTI] Updating badge count. isDuplicate=$isDuplicate, message=$message',
    );
    // Always increment count, but suppress snackbar for duplicates
    setState(() {
      _notificationCount += 1;
      _lastNotification = message;
      _lastNotificationMessage = message;
      _lastNotificationAt = now;
      debugPrint('[DEBUG] [NOTI] Badge count updated to: $_notificationCount');
    });

    // Only show snackbar if not a duplicate to avoid UI spam
    if (!isDuplicate && showSnackBar) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showNotificationsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'การแจ้งเตือน',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('จำนวน: $_notificationCount'),
              const SizedBox(height: 8),
              Text(_lastNotification),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _notificationCount = 0;
                    });
                  },
                  child: const Text('ล้างตัวนับ'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _connectSocket() {
    final String? channelId = _requireChannelId();
    if (channelId == null) {
      return;
    }

    _socket?.dispose();
    _socket = null;
    _socketChannelId = null;

    debugPrint(
      '[DEBUG] [SOCKET] Connecting to channel: $channelId, clientId: $_clientId',
    );
    _logRealtime('socket_connecting channelId=$channelId clientId=$_clientId');

    final io.Socket socket = io.io(socketBaseUrl, <String, dynamic>{
      'transports': <String>['websocket'],
      'autoConnect': false,
      'forceNew': true,
      'multiplex': false,
      'query': <String, dynamic>{'channelId': channelId, 'clientId': _clientId},
    });

    socket.onConnect((_) {
      _socketChannelId = channelId;
      debugPrint(
        '[DEBUG] [SOCKET] Connected! Channel: $channelId, socketId: ${socket.id}',
      );
      _logRealtime(
        'socket_connected channelId=$channelId clientId=$_clientId socketId=${socket.id}',
      );
      _setInlineError('');
      _notifyUser('เชื่อมต่อระบบเรียลไทม์สำเร็จ');
    });

    debugPrint('[DEBUG] [SOCKET] Registering ts_changed listener');
    socket.on('ts_changed', (dynamic payload) {
      debugPrint('[DEBUG] [SOCKET] EVENT RECEIVED: $payload');
      if (payload is Map<String, dynamic>) {
        final String? activeChannelId = _channelId;
        if (activeChannelId == null) {
          _logRealtime('event_ignored missing_active_channel payload=$payload');
          return;
        }

        final dynamic rawChannelId = payload['channelId'];
        if (rawChannelId is String && rawChannelId != activeChannelId) {
          _logRealtime(
            'event_ignored channel_mismatch payloadChannel=$rawChannelId activeChannel=$activeChannelId',
          );
          return;
        }

        final dynamic rawId = payload['id'] ?? payload['_id'];
        final dynamic rawTs = payload['ts'];
        final dynamic rawClientId = payload['clientId'];
        final bool isFromThisDevice =
            rawClientId is String && rawClientId == _clientId;
        final bool isDeleted = payload['deleted'] == true;

        debugPrint(
          '[DEBUG] [EVENT] itemId=$rawId, channel=$rawChannelId, fromClient=$rawClientId, self=$isFromThisDevice, deleted=$isDeleted',
        );
        _logRealtime(
          'event_received itemId=$rawId channelId=$rawChannelId fromClientId=$rawClientId self=$isFromThisDevice deleted=$isDeleted',
        );

        if (rawId is String) {
          if (isDeleted) {
            if (!mounted) {
              return;
            }

            setState(() {
              _items = _items
                  .where((ItemRecord item) => item.id != rawId)
                  .toList();
            });

            final String deleteMsg = isFromThisDevice
                ? 'เรียลไทม์: คุณลบรายการจากเครื่องนี้'
                : 'เรียลไทม์: มีการลบรายการจากอีกเครื่อง';
            debugPrint('[DEBUG] [NOTI] Triggering notification: $deleteMsg');
            _notifyUser(deleteMsg, showSnackBar: false);
            return;
          }

          final ItemRecord? existingItem = _findItemById(rawId);

          if (existingItem == null) {
            // For newly created items, we may only receive id/ts in the event.
            // Refetch to retrieve the complete record (e.g., name).
            unawaited(_fetchItems());
            final String createMsg = isFromThisDevice
                ? 'เรียลไทม์: คุณเพิ่มรายการจากเครื่องนี้'
                : 'เรียลไทม์: มีการเพิ่มรายการจากอีกเครื่อง';
            debugPrint('[DEBUG] [NOTI] Triggering notification: $createMsg');
            _notifyUser(createMsg, showSnackBar: false);
            return;
          }

          final String parsedTs =
              ItemRecord.tryParseTsObjectId(rawTs) ?? existingItem.ts;
          final ItemRecord updatedItem = ItemRecord(
            id: rawId,
            name: existingItem.name,
            ts: parsedTs,
          );
          _applyItemUpdate(updatedItem);

          // Notify with unique message including item name and partial ts
          final String originLabel = isFromThisDevice
              ? 'เครื่องนี้'
              : 'อีกเครื่อง';
          final String notifyMsg =
              'เรียลไทม์: $originLabel อัปเดต ${updatedItem.name} - ts: ${parsedTs.substring(0, 8)}...';
          debugPrint('[DEBUG] [NOTI] Triggering notification: $notifyMsg');
          _notifyUser(notifyMsg, showSnackBar: false);
        }
      }
    });

    socket.onConnectError((dynamic error) {
      _logRealtime('socket_connect_error channelId=$channelId error=$error');
      final String message = 'ไม่สามารถเชื่อมต่อ socket gateway ได้: $error';
      _setInlineError(message);
    });

    socket.onError((dynamic error) {
      _logRealtime('socket_error channelId=$channelId error=$error');
      final String message = 'เกิดข้อผิดพลาดระหว่างทำงานของ socket: $error';
      _setInlineError(message);
    });

    socket.onDisconnect((dynamic _) {
      _socketChannelId = null;
      _logRealtime(
        'socket_disconnected channelId=$channelId clientId=$_clientId',
      );
      const String message = 'การเชื่อมต่อ socket ถูกตัด';
      _setInlineError(message);
    });

    socket.connect();
    _socket = socket;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isSocketConnected = _socket?.connected ?? false;
    final String backendStatusText = _isBackendConnected == null
        ? 'ยังไม่ตรวจสอบ BE'
        : (_isBackendConnected! ? 'BE พร้อมใช้งาน' : 'BE ไม่พร้อมใช้งาน');
    final IconData backendStatusIcon = _isBackendConnected == null
        ? Icons.cloud_queue
        : (_isBackendConnected! ? Icons.cloud_done : Icons.cloud_off);
    final Color backendChipBg = _isBackendConnected == null
        ? const Color(0xFF4B5563)
        : (_isBackendConnected!
              ? const Color(0xFF16A34A)
              : const Color(0xFFDC2626));
    final Color backendChipFg = Colors.white;
    final Color socketChipBg = isSocketConnected
        ? const Color(0xFF0284C7)
        : const Color(0xFFB91C1C);
    final Color socketChipFg = Colors.white;
    final Color channelChipBg = const Color(0xFF1D4ED8);
    final Color channelChipFg = Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('เดโมเปลี่ยนค่า ts แบบเรียลไทม์'),
        actions: <Widget>[
          IconButton(
            onPressed: _showNotificationsSheet,
            icon: Badge(
              isLabelVisible: _notificationCount > 0,
              label: Text('$_notificationCount'),
              child: const Icon(Icons.notifications),
            ),
          ),
          IconButton(onPressed: _fetchItems, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'ตั้งค่าช่องทาง',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _phoneChannelController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'เบอร์โทรช่องทาง (ไทย)',
                                hintText: 'เช่น 0812345678',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: _applyPhoneChannel,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('ตั้งค่า'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          Chip(
                            backgroundColor: backendChipBg,
                            avatar: Icon(
                              backendStatusIcon,
                              size: 18,
                              color: backendChipFg,
                            ),
                            label: Text(
                              backendStatusText,
                              style: TextStyle(color: backendChipFg),
                            ),
                          ),
                          Chip(
                            backgroundColor: socketChipBg,
                            avatar: Icon(
                              isSocketConnected ? Icons.wifi : Icons.wifi_off,
                              size: 18,
                              color: socketChipFg,
                            ),
                            label: Text(
                              isSocketConnected
                                  ? 'Socket เชื่อมต่อ'
                                  : 'Socket ไม่เชื่อมต่อ',
                              style: TextStyle(color: socketChipFg),
                            ),
                          ),
                          Chip(
                            backgroundColor: channelChipBg,
                            avatar: Icon(
                              Icons.sim_card,
                              size: 18,
                              color: channelChipFg,
                            ),
                            label: Text(
                              'ช่องทาง: ${_channelId ?? '-'}',
                              style: TextStyle(color: channelChipFg),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'ชื่อรายการ',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _createItem,
                        icon: const Icon(Icons.add),
                        label: const Text('เพิ่ม'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_isLoading) const LinearProgressIndicator(),
              if (_error != null && _error!.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8, bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          'ยังไม่มีรายการในช่องทางนี้',
                          style: theme.textTheme.bodyLarge,
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final ItemRecord item = _items[index];
                          return Card(
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.inventory_2_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                                title: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const SizedBox(height: 6),
                                    SelectableText(
                                      'รหัส: ${item.id}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 2),
                                    SelectableText(
                                      'ts: ${item.ts}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    IconButton(
                                      tooltip: 'อัปเดต ts',
                                      onPressed:
                                          _updatingItemIds.contains(item.id)
                                          ? null
                                          : () => _refreshTs(item.id),
                                      icon: const Icon(Icons.schedule_rounded),
                                    ),
                                    IconButton(
                                      tooltip: 'ลบรายการ',
                                      onPressed:
                                          _deletingItemIds.contains(item.id)
                                          ? null
                                          : () => _confirmDeleteItem(item),
                                      icon: const Icon(Icons.delete_rounded),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

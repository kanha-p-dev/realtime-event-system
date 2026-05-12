import 'dart:async';
import 'dart:convert';

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
  runApp(const RealtimeApp());
}

class RealtimeApp extends StatelessWidget {
  const RealtimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Realtime Event Demo',
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
  List<ItemRecord> _items = <ItemRecord>[];
  final Set<String> _updatingItemIds = <String>{};
  bool _isLoading = false;
  String? _error;
  int _notificationCount = 0;
  String _lastNotification = 'No notifications yet';
  io.Socket? _socket;

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
    _fetchItems();
    _connectSocket();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _socket?.dispose();
    super.dispose();
  }

  Future<void> _fetchItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final Uri uri = Uri.parse('$apiBaseUrl/items');
      final http.Response response = await http.get(uri).timeout(apiTimeout);

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

      setState(() {
        _items = loadedItems;
      });
    } catch (error) {
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

    try {
      final Uri uri = Uri.parse('$apiBaseUrl/items');
      final http.Response response = await http
          .post(
            uri,
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, String>{'name': trimmedName}),
          )
          .timeout(apiTimeout);

      if (response.statusCode != 201) {
        throw Exception('สร้างรายการไม่สำเร็จ (สถานะ: ${response.statusCode})');
      }

      _nameController.clear();
      await _fetchItems();
    } catch (error) {
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

    final ItemRecord? currentItem = _findItemById(id);

    setState(() {
      _updatingItemIds.add(id);
    });

    try {
      final Uri uri = Uri.parse('$apiBaseUrl/items/$id/ts');
      final http.Response response = await http.patch(uri).timeout(apiTimeout);

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
      return;
    }

    setState(() {
      _notificationCount += 1;
      _lastNotification = message;
    });

    if (showSnackBar) {
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
                'Notifications',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Count: $_notificationCount'),
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
                  child: const Text('Clear badge'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _connectSocket() {
    final io.Socket socket = io.io(socketBaseUrl, <String, dynamic>{
      'transports': <String>['websocket'],
      'autoConnect': false,
    });

    socket.onConnect((_) {
      _setInlineError('');
      _notifyUser('Connected to realtime gateway');
    });

    socket.on('ts_changed', (dynamic payload) {
      if (payload is Map<String, dynamic>) {
        final dynamic rawId = payload['id'] ?? payload['_id'];
        final dynamic rawTs = payload['ts'];

        if (rawId is String) {
          final ItemRecord? existingItem = _findItemById(rawId);
          final String parsedTs =
              ItemRecord.tryParseTsObjectId(rawTs) ?? existingItem?.ts ?? rawId;
          final ItemRecord updatedItem = ItemRecord(
            id: rawId,
            name: existingItem?.name ?? 'unknown',
            ts: parsedTs,
          );
          _applyItemUpdate(updatedItem);

          // Notify with unique message including item name and partial ts
          final String notifyMsg =
              'Real-time: ${updatedItem.name} - ts: ${parsedTs.substring(0, 8)}...';
          _notifyUser(notifyMsg, showSnackBar: false);
        }
      }
    });

    socket.onConnectError((dynamic error) {
      final String message = 'ไม่สามารถเชื่อมต่อ socket gateway ได้: $error';
      _setInlineError(message);
    });

    socket.onError((dynamic error) {
      final String message = 'เกิดข้อผิดพลาดระหว่างทำงานของ socket: $error';
      _setInlineError(message);
    });

    socket.onDisconnect((dynamic _) {
      const String message = 'การเชื่อมต่อ socket ถูกตัด';
      _setInlineError(message);
    });

    socket.connect();
    _socket = socket;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime ts Change Demo'),
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Item name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _createItem,
                  child: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading) const LinearProgressIndicator(),
            if (_error != null && _error!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: _items.length,
                itemBuilder: (BuildContext context, int index) {
                  final ItemRecord item = _items[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_rounded),
                      title: Text(item.name),
                      subtitle: Text('id: ${item.id}\nts: ${item.ts}'),
                      trailing: OutlinedButton.icon(
                        onPressed: _updatingItemIds.contains(item.id)
                            ? null
                            : () => _refreshTs(item.id),
                        icon: const Icon(Icons.update),
                        label: const Text('Update ts'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

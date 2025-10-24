// 🎯 lib/pages/sendpage.dart (Dropdown ปลายทางเลือกชื่อผู้ใช้ทุกคน + แก้ Overflow + แสดงพิกัดผู้รับ)

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class SendPage extends StatefulWidget {
  final String? senderPhone;
  const SendPage({super.key, this.senderPhone});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  static const String USER_COLLECTION = 'user';
  final _formKey = GlobalKey<FormState>();
  final db = FirebaseFirestore.instance;

  // -------- Sender state --------
  bool _loadingSender = true;
  Map<String, dynamic>? _senderDoc;
  List<Map<String, dynamic>> _senderAddresses = [];
  Map<String, dynamic>? _selectedSenderAddress;

  // -------- Receiver state --------
  final _receiverPhoneCtl = TextEditingController(); // ทางเลือก: ค้นหาด้วยเบอร์
  bool _loadingReceiver = false; // สำหรับค้นหาด้วยเบอร์
  Map<String, dynamic>? _receiverDoc;
  List<Map<String, dynamic>> _receiverAddresses = [];
  Map<String, dynamic>? _selectedReceiverAddress;

  // ✅ รายชื่อผู้ใช้ทั้งหมดสำหรับ dropdown
  bool _loadingAllUsers = true;
  List<Map<String, dynamic>> _allUsers = []; // {name, phone, addresses: []}
  Map<String, dynamic>? _selectedUserForReceiver; // user ที่เลือกเป็นผู้รับ

  bool _showAddressDropdown = false;

  // -------- Items --------
  final List<_ItemRow> _items = [_ItemRow()];
  bool _submitting = false;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchSenderData();
    _fetchAllUsers(); // โหลดรายชื่อ user ทั้งหมด
  }

  // ---------------- Sender ----------------
  Future<void> _fetchSenderData() async {
    final phone = widget.senderPhone;
    if (phone == null || phone.isEmpty) {
      setState(() => _loadingSender = false);
      return;
    }

    try {
      final doc = await db.collection(USER_COLLECTION).doc(phone).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final addrs = (data['addresses'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _senderDoc = data..['phone'] = phone;
          _senderAddresses = addrs;
          if (_senderAddresses.isNotEmpty) {
            _selectedSenderAddress = _senderAddresses.first;
          }
        });
      }
    } catch (e) {
      log('fetchSender error: $e');
    } finally {
      if (mounted) setState(() => _loadingSender = false);
    }
  }

  // ---------------- All users for receiver dropdown ----------------
  Future<void> _fetchAllUsers() async {
    try {
      // NOTE: ถ้าผู้ใช้เยอะมาก ควรทำ pagination/limit
      final qs = await db.collection(USER_COLLECTION).get();
      final list = <Map<String, dynamic>>[];
      for (final d in qs.docs) {
        final m = d.data() as Map<String, dynamic>;
        final name = (m['name'] as String?) ?? '';
        final phone = d.id; // doc id เป็นเบอร์โทรใน schema
        final addrs = (m['addresses'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        list.add({'name': name, 'phone': phone, 'addresses': addrs});
      }
      if (!mounted) return;
      setState(() {
        _allUsers = list
          ..sort(
            (a, b) => (a['name'] ?? '').toString().compareTo(
              (b['name'] ?? '').toString(),
            ),
          );
      });
    } catch (e) {
      log('fetchAllUsers error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โหลดรายชื่อผู้ใช้ไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingAllUsers = false);
    }
  }

  void _resetForm() {
    setState(() {
      _receiverPhoneCtl.clear();
      _receiverDoc = null;
      _receiverAddresses = [];
      _selectedReceiverAddress = null;
      _selectedUserForReceiver = null;
      _showAddressDropdown = false;
      _items
        ..clear()
        ..add(_ItemRow());
      _submitting = false;
    });
  }

  @override
  void dispose() {
    _receiverPhoneCtl.dispose();
    super.dispose();
  }

  // -- ทางเลือก: ค้นหาด้วยเบอร์ (ยังคงไว้) --
  Future<void> _searchReceiverByPhone() async {
    final phone = _receiverPhoneCtl.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกเบอร์โทรศัพท์ผู้รับ')),
      );
      return;
    }
    setState(() => _loadingReceiver = true);
    try {
      final doc = await db.collection(USER_COLLECTION).doc(phone).get();
      if (!doc.exists) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่พบผู้ใช้หมายเลข $phone')));
        return;
      }
      final data = doc.data()!;
      final addrs = (data['addresses'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _selectedUserForReceiver = {
          'name': (data['name'] as String?) ?? '',
          'phone': phone,
          'addresses': addrs,
        };
        _receiverDoc = data..['phone'] = phone;
        _receiverAddresses = addrs;
        _selectedReceiverAddress = _receiverAddresses.isNotEmpty
            ? _receiverAddresses.first
            : null;
        _showAddressDropdown = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ค้นหาผู้รับไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _loadingReceiver = false);
    }
  }

  void _addItemRow() => setState(() => _items.add(_ItemRow()));
  void _removeItemRow(int index) {
    if (_items.length > 1) {
      setState(() => _items.removeAt(index));
    }
  }

  Future<String?> _uploadItemImage(XFile imageFile) async {
    try {
      const cloudName = 'drskwb4o3';
      const uploadPreset = 'images';
      const folder = 'deliveries';

      final publicId =
          '$folder/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      final req = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = folder
        ..fields['public_id'] = publicId
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return json['secure_url'] as String?;
      } else {
        throw Exception('Upload failed with status ${res.statusCode}: $body');
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
      return null;
    }
  }

  Future<void> _submit() async {
    final senderPhone = widget.senderPhone;
    if (senderPhone == null || senderPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบเบอร์ผู้ส่ง (โปรดเข้าสู่ระบบอีกครั้ง)'),
        ),
      );
      return;
    }

    if (_selectedSenderAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกที่อยู่ต้นทาง (ผู้ส่ง)')),
      );
      return;
    }

    // ✅ ต้องเลือกผู้รับและที่อยู่จาก dropdown
    if (_selectedUserForReceiver == null || _selectedReceiverAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกผู้รับและที่อยู่ปลายทาง')),
      );
      return;
    }

    final validItems = _items
        .where((item) => item.name.trim().isNotEmpty)
        .toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเพิ่มสินค้าอย่างน้อย 1 รายการ')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // เตรียมรูปสินค้า
      final itemsForPayload = <Map<String, dynamic>>[];
      for (final item in validItems) {
        String? imageUrl;
        if (item.pickedImage != null) {
          imageUrl = await _uploadItemImage(item.pickedImage!);
        }
        itemsForPayload.add({
          'name': item.name.trim(),
          'qty': item.qty,
          'weight': item.weight,
          'note': item.note?.trim(),
          'imageUrl': imageUrl,
        });
      }

      // Sender
      final senderName = (_senderDoc?['name'] as String?) ?? '';
      final sAddr = _selectedSenderAddress!;
      final senderAddr = {
        'address': sAddr['address'] ?? '',
        'lat': (sAddr['lat'] as num?)?.toDouble(),
        'lng': (sAddr['lng'] as num?)?.toDouble(),
      };

      // Receiver จาก dropdown รายชื่อทุก user
      final receiverPhone = _selectedUserForReceiver!['phone'] as String;
      final receiverName = (_selectedUserForReceiver!['name'] as String?) ?? '';
      final rAddr = _selectedReceiverAddress!;
      final receiverAddr = {
        'address': rAddr['address'] ?? '',
        'lat': (rAddr['lat'] as num?)?.toDouble(),
        'lng': (rAddr['lng'] as num?)?.toDouble(),
      };

      final payload = {
        'senderId': senderPhone,
        'senderName': senderName,
        'senderAddress': senderAddr,
        'receiverId': receiverPhone,
        'receiverName': receiverName,
        'receiverPhone': receiverPhone,
        'receiverAddress': receiverAddr,
        'items': itemsForPayload,
        'status': 'created',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await db.collection('deliveries').add(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สร้างคำสั่งส่งพัสดุสำเร็จ')),
      );
      _resetForm();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- UI ส่วนผู้ส่ง ---
    final senderSection = _loadingSender
        ? const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24.0),
              child: CircularProgressIndicator(),
            ),
          )
        : _senderDoc == null
        ? ListTile(
            leading: const Icon(Icons.error_outline, color: Colors.red),
            title: const Text('ไม่พบข้อมูลผู้ส่ง'),
            subtitle: const Text('โปรดลองเข้าสู่ระบบอีกครั้ง'),
            contentPadding: EdgeInsets.zero,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ผู้ส่ง', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.person_pin_circle_outlined,
                  color: Colors.blueGrey,
                ),
                title: Text(
                  _senderDoc?['name'] ?? '(ไม่มีชื่อ)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(widget.senderPhone ?? ''),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              if (_senderAddresses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'คุณยังไม่มีที่อยู่ที่บันทึกไว้ (โปรดเพิ่มในหน้าโปรไฟล์)',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                )
              else
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedSenderAddress,
                  items: _senderAddresses.map((addr) {
                    return DropdownMenuItem(
                      value: addr,
                      child: Text(
                        addr['address'] ?? '(ไม่มีข้อมูลที่อยู่)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedSenderAddress = v),
                  decoration: const InputDecoration(
                    labelText: 'เลือกที่อยู่ต้นทาง',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  validator: (value) =>
                      value == null ? 'กรุณาเลือกที่อยู่ต้นทาง' : null,
                ),
              if (_selectedSenderAddress != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'พิกัด: (${_selectedSenderAddress?['lat'] ?? '-'}, ${_selectedSenderAddress?['lng'] ?? '-'})',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('ดูบนแผนที่'),
                      onPressed: () {
                        final lat = (_selectedSenderAddress?['lat'] as num?)
                            ?.toDouble();
                        final lng = (_selectedSenderAddress?['lng'] as num?)
                            ?.toDouble();
                        if (lat != null && lng != null) {
                          _openInMaps(
                            lat: lat,
                            lng: lng,
                            label: 'ที่อยู่ผู้ส่ง',
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ที่อยู่นี้ยังไม่มีพิกัด'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ],
          );

    // --- UI ส่วนผู้รับ (เลือกจากรายชื่อทุก user) ---
    final receiverSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ผู้รับ', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),

        // ✅ Dropdown #1: เลือก "ผู้รับ" จากผู้ใช้ทั้งหมด
        _loadingAllUsers
            ? const Padding(
                padding: EdgeInsets.all(8.0),
                child: LinearProgressIndicator(),
              )
            : DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedUserForReceiver,
                hint: const Text('— เลือกผู้รับ —'),
                items: _allUsers.map((u) {
                  final name = (u['name'] as String?)?.trim();
                  final phone = (u['phone'] as String?) ?? '';
                  final label = (name == null || name.isEmpty)
                      ? phone
                      : '$name ($phone)';
                  return DropdownMenuItem(
                    value: u,
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (u) {
                  setState(() {
                    _selectedUserForReceiver = u;
                    _receiverDoc = {
                      'name': u?['name'] ?? '',
                      'phone': u?['phone'] ?? '',
                    };
                    _receiverAddresses =
                        (u?['addresses'] as List<Map<String, dynamic>>?) ??
                        <Map<String, dynamic>>[];
                    _selectedReceiverAddress = _receiverAddresses.isNotEmpty
                        ? _receiverAddresses.first
                        : null;
                    _showAddressDropdown = true; // แสดง dropdown ที่อยู่
                  });
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                validator: (value) => value == null ? 'กรุณาเลือกผู้รับ' : null,
              ),

        const SizedBox(height: 12),

        // ✅ Dropdown #2: เลือก “ที่อยู่ผู้รับ”  (แก้ overflow โดยไม่วางปุ่มใน child)
        if (_showAddressDropdown)
          (_receiverAddresses.isEmpty)
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'ผู้รับยังไม่มีที่อยู่ที่บันทึกไว้',
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<Map<String, dynamic>>(
                      value: _selectedReceiverAddress,
                      hint: const Text('— เลือกที่อยู่ผู้รับ —'),
                      items: _receiverAddresses.map((addr) {
                        return DropdownMenuItem(
                          value: addr,
                          child: Text(
                            addr['address'] ?? '(ไม่มีข้อมูลที่อยู่)',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setState(() => _selectedReceiverAddress = v),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      validator: (value) =>
                          value == null ? 'กรุณาเลือกที่อยู่ผู้รับ' : null,
                    ),

                    // 🔎 แสดงพิกัด + ปุ่มดูแผนที่ แยกบรรทัด (ไม่ overflow)
                    if (_selectedReceiverAddress != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 18,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'พิกัด: ${(_selectedReceiverAddress?['lat'] ?? '-')} , ${(_selectedReceiverAddress?['lng'] ?? '-')}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'ดูบนแผนที่',
                            icon: const Icon(Icons.map_outlined),
                            onPressed: () {
                              final lat =
                                  (_selectedReceiverAddress?['lat'] as num?)
                                      ?.toDouble();
                              final lng =
                                  (_selectedReceiverAddress?['lng'] as num?)
                                      ?.toDouble();
                              final name =
                                  (_receiverDoc?['name'] as String?) ??
                                  'ผู้รับ';
                              if (lat != null && lng != null) {
                                _openInMaps(
                                  lat: lat,
                                  lng: lng,
                                  label: 'ที่อยู่ผู้รับ $name',
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ที่อยู่นี้ยังไม่มีพิกัด'),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

        // ----- (ตัวเลือก) ค้นหาด้วยเบอร์เดิม -----
        const SizedBox(height: 16),
        Text('หรือค้นหาผู้รับด้วยเบอร์โทร (ทางเลือก)'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _receiverPhoneCtl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: 'เบอร์โทรศัพท์ผู้รับ',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loadingReceiver ? null : _searchReceiverByPhone,
              icon: _loadingReceiver
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: const Text('ค้นหา'),
            ),
          ],
        ),
        // ---------------------------------------
      ],
    );

    // --- Main Scaffold ---
    return Scaffold(
      appBar: AppBar(
        title: const Text('ส่งพัสดุ'),
        actions: [
          if (widget.senderPhone != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  'ผู้ส่ง: ${widget.senderPhone!}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Sender Section
            senderSection,
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Receiver Section
            receiverSection,
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Items Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'รายการสินค้า',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: _addItemRow,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('เพิ่มสินค้า'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Item Cards
            ...List.generate(_items.length, (index) {
              final item = _items[index];
              return Padding(
                key: ValueKey(item.id),
                padding: const EdgeInsets.only(bottom: 12),
                child: _ItemCard(
                  item: item,
                  picker: _picker,
                  onRemove: _items.length > 1
                      ? () => _removeItemRow(index)
                      : null,
                ),
              );
            }),
            const SizedBox(height: 24),

            // Submit
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('ยืนยันส่งพัสดุ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  } // End build

  Future<void> _openInMaps({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final encodedLabel = Uri.encodeComponent(label ?? 'ตำแหน่ง');
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng&query_place_id=$encodedLabel',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // fallback แบบ geo: (บางอุปกรณ์)
      final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedLabel)');
      if (await canLaunchUrl(geo)) {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ไม่สามารถเปิดแผนที่ได้')));
      }
    }
  }
}

// ================== Item widgets ==================

class _ItemRow {
  _ItemRow();
  final String id = UniqueKey().toString();
  String name = '';
  int qty = 1;
  double? weight;
  String? note;
  XFile? pickedImage;
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.item,
    required this.picker,
    this.onRemove,
    super.key,
  });

  final _ItemRow item;
  final ImagePicker picker;
  final VoidCallback? onRemove;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  final _nameCtl = TextEditingController();
  final _qtyCtl = TextEditingController(text: '1');
  final _weightCtl = TextEditingController();
  final _noteCtl = TextEditingController();

  XFile? _pickedImage;

  @override
  void initState() {
    super.initState();
    _nameCtl.text = widget.item.name;
    _qtyCtl.text = widget.item.qty.toString();
    _weightCtl.text = widget.item.weight?.toString() ?? '';
    _noteCtl.text = widget.item.note ?? '';
    _pickedImage = widget.item.pickedImage;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _qtyCtl.dispose();
    _weightCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  void _sync() {
    widget.item
      ..name = _nameCtl.text
      ..qty = int.tryParse(_qtyCtl.text) ?? 1
      ..weight = double.tryParse(_weightCtl.text)
      ..note = _noteCtl.text.isNotEmpty ? _noteCtl.text : null
      ..pickedImage = _pickedImage;
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('ถ่ายรูป'),
                onTap: () {
                  Navigator.pop(context, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('เลือกจากคลังภาพ'),
                onTap: () {
                  Navigator.pop(context, ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );

    if (source != null) {
      try {
        final XFile? file = await widget.picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1024,
        );
        if (file != null) {
          setState(() {
            _pickedImage = file;
            _sync();
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกรูป: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pickedImage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_pickedImage!.path),
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _pickedImage == null ? 'เพิ่มรูปพัสดุ' : 'เปลี่ยนรูป',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(
                labelText: 'ชื่อสินค้า',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _sync(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'จำนวน',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _weightCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'น้ำหนัก (กก.)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtl,
              decoration: const InputDecoration(
                labelText: 'รายละเอียดสินค้า',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _sync(),
            ),
            if (widget.onRemove != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('ลบรายการนี้'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

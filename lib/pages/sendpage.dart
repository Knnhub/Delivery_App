import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:DefaultFirebaseOptions.dart'; // ✅ ดึงเบอร์จาก Auth
// import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SendPage extends StatefulWidget {
  final String? senderPhone;

  const SendPage({super.key, this.senderPhone});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  static const String RECEIVER_COLLECTION = 'user';
  final _formKey = GlobalKey<FormState>();

  // ผู้ส่ง (ดึงจาก Firebase Auth)
  // String? _senderPhone;

  // ค้นผู้รับด้วยเบอร์โทร
  final _receiverPhoneCtl = TextEditingController();

  // สถานะโหลด/ข้อมูลผู้รับ
  bool _loadingReceiver = false;
  Map<String, dynamic>? _receiverDoc;
  List<Map<String, dynamic>> _receiverAddresses = [];
  Map<String, dynamic>? _selectedReceiverAddress;

  // รายการสินค้า (เพิ่ม/ลบได้)
  final List<_ItemRow> _items = [_ItemRow()];

  bool _submitting = false;

  // @override
  // void initState() {
  //   super.initState();
  //   _initSenderPhone();
  // }

  /// โหลดเบอร์ผู้ส่งจาก Firestore โดยอิง uid ของผู้ใช้ที่ล็อกอิน (กรณีไม่ได้ใช้ Phone Auth)
  // Future<String?> _loadSenderPhoneFromFirestore() async {
  //   final user = FirebaseAuth.instance.currentUser;
  //   await user?.reload();
  //   final uid = user?.uid;
  //   if (uid == null) return null;

  //   final db = FirebaseFirestore.instance;

  //   // ทางเลือก A: มี mapping แยก เช่น usersByUid/{uid} -> { phone: "+66..." }
  //   try {
  //     final byUidDoc = await db.collection('usersByUid').doc(uid).get();
  //     if (byUidDoc.exists) {
  //       final phone = byUidDoc.data()?['phone'] as String?;
  //       if (phone != null && phone.trim().isNotEmpty) return phone.trim();
  //     }
  //   } catch (_) {}

  //   // ทางเลือก B: collection 'user' เก็บฟิลด์ 'uid' ไว้
  //   try {
  //     final snap = await db
  //         .collection('user')
  //         .where('uid', isEqualTo: uid)
  //         .limit(1)
  //         .get();

  //     if (snap.docs.isNotEmpty) {
  //       final doc = snap.docs.first;
  //       // ใช้ฟิลด์ phone ถ้ามี; ถ้าไม่มี ใช้ doc.id (กรณีตั้ง docId=phone)
  //       final data = doc.data();
  //       final phone = (data['phone'] as String?) ?? doc.id;
  //       if (phone.trim().isNotEmpty) return phone.trim();
  //     }
  //   } catch (_) {}

  //   return null;
  // }

  // Future<void> _initSenderPhone() async {
  //   final user = FirebaseAuth.instance.currentUser;
  //   await user?.reload();

  //   // 1) ถ้าเป็น Phone Auth จริง ๆ จะมีค่า (กรณีนี้ยังรองรับไว้)
  //   final authPhone = user?.phoneNumber;
  //   if (authPhone != null && authPhone.isNotEmpty) {
  //     setState(() => _senderPhone = authPhone.trim());
  //     return;
  //   }

  //   // 2) Fallback: ไปดึงจาก Firestore ด้วย uid
  //   final phoneFromDb = await _loadSenderPhoneFromFirestore();
  //   setState(() => _senderPhone = phoneFromDb); // อาจเป็น null ถ้ายังหาไม่เจอ
  // }

  // แปลง +66xxxxxxxxx → 0xxxxxxxxx (ออปชัน)
  // String? _toLocalPhone(String? e164) {
  //   if (e164 == null) return null;
  //   if (e164.startsWith('+66')) {
  //     return '0${e164.substring(3)}';
  //   }
  //   return e164;
  // }

  @override
  void dispose() {
    _receiverPhoneCtl.dispose();
    super.dispose();
  }

  Future<void> _searchReceiverByPhone() async {
    final phone = _receiverPhoneCtl.text.trim();
    debugPrint('[search] phone="$phone"'); // ลบได้
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกเบอร์โทรศัพท์ผู้รับ')),
      );
      return;
    }

    setState(() {
      _loadingReceiver = true;
      _receiverDoc = null;
      _receiverAddresses = [];
      _selectedReceiverAddress = null;
    });

    try {
      final doc = await FirebaseFirestore.instance
          .collection(RECEIVER_COLLECTION)
          .doc(phone)
          .get();

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
        _receiverDoc = data..['phone'] = phone;
        _receiverAddresses = addrs;
        if (_receiverAddresses.isNotEmpty) {
          _selectedReceiverAddress = _receiverAddresses.first;
        }
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
    if (_items.length == 1) return;
    setState(() => _items.removeAt(index));
  }

  Future<void> _submit() async {
    // ✅ ต้องมีเบอร์ผู้ส่งจาก Auth
    debugPrint('--- Checking senderPhone values ---');
    debugPrint(
      'Value from previous page (widget.senderPhone): ${widget.senderPhone}',
    );
    debugPrint(
      'Value from initState state (_senderPhone): ${widget.senderPhone}',
    );
    debugPrint('------------------------------------');

    final senderPhone = widget.senderPhone;
    if (senderPhone == null || senderPhone.isEmpty) {
      debugPrint('[submit][abort] no sender phone'); // ลบได้
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบเบอร์ผู้ส่ง (โปรดเข้าสู่ระบบด้วยเบอร์โทร)'),
        ),
      );
      return;
    }

    // ตรวจสอบผู้รับ/ที่อยู่/สินค้า
    if (_receiverDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาค้นหาและเลือกผู้รับก่อน')),
      );
      return;
    }
    if (_selectedReceiverAddress == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเลือกที่อยู่ผู้รับ')));
      return;
    }
    final items = _items
        .map((e) => e.toMap())
        .where((m) => (m['name'] as String).trim().isNotEmpty)
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเพิ่มสินค้าอย่างน้อย 1 รายการ')),
      );
      return;
    }

    setState(() => _submitting = true);

    debugPrint('[submit] receiverDoc=$_receiverDoc'); // ลบได้
    debugPrint('[submit] items=$items'); // ลบได้
    debugPrint('[submit] selectedAddress=$_selectedReceiverAddress'); // ลบได้

    try {
      final receiverPhone = _receiverDoc!['phone'] as String;
      final receiverName = (_receiverDoc!['name'] ?? '') as String? ?? '';
      final addr = _selectedReceiverAddress!;
      final receiverAddr = {
        'address': addr['address'] ?? '',
        'lat': (addr['lat'] as num?)?.toDouble(),
        'lng': (addr['lng'] as num?)?.toDouble(),
      };

      final payload = {
        'senderId': senderPhone, // ✅ ใช้เบอร์จาก Auth
        'receiverId': receiverPhone,
        'receiverName': receiverName,
        'receiverPhone': receiverPhone,
        'receiverAddress': receiverAddr,
        'items': items, // [{name, qty, weight, note}]
        'status': 'created',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('deliveries').add(payload);
      debugPrint('[submit] created OK'); // ลบได้

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สร้างคำสั่งส่งพัสดุสำเร็จ')),
      );
      // Navigator.maybePop(context);
    } catch (e, st) {
      debugPrint('[submit][error] $e\\n$st');
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
    final addrHint = _selectedReceiverAddress == null
        ? '—'
        : '${_selectedReceiverAddress?['address'] ?? ''}'
              '${_selectedReceiverAddress?['lat'] != null ? '\n(${_selectedReceiverAddress?['lat']}, ${_selectedReceiverAddress?['lng']})' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('ส่งพัสดุ'),
        actions: [
          if (widget.senderPhone != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  widget.senderPhone!, // โชว์ไว้ตรวจสอบ (จะเอาออกก็ได้)
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
            // ค้นหาผู้รับ
            Text('ผู้รับ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _receiverPhoneCtl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'เบอร์โทรศัพท์ผู้รับ',
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
            const SizedBox(height: 12),

            if (_receiverDoc != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(_receiverDoc?['name'] ?? '(ไม่มีชื่อ)'),
                  subtitle: Text(_receiverDoc?['phone'] ?? ''),
                ),
              ),
              const SizedBox(height: 8),

              // เลือกที่อยู่ผู้รับ
              DropdownButtonFormField<Map<String, dynamic>>(
                value: _selectedReceiverAddress,
                items: _receiverAddresses.map((m) {
                  final label = (m['address'] ?? '') as String? ?? '';
                  return DropdownMenuItem(
                    value: m,
                    child: Text(
                      label.isEmpty ? '(ไม่มีที่อยู่)' : label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedReceiverAddress = v),
                decoration: const InputDecoration(
                  labelText: 'ที่อยู่ผู้รับ',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(addrHint, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
            ],

            // รายการสินค้า (หลายชิ้น)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'รายการสินค้า',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: _addItemRow,
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่มสินค้า'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            ...List.generate(_items.length, (index) {
              final item = _items[index];
              return Padding(
                key: ValueKey(item.id),
                padding: const EdgeInsets.only(bottom: 12),
                child: _ItemCard(
                  item: item,
                  onRemove: _items.length == 1
                      ? null
                      : () => _removeItemRow(index),
                ),
              );
            }),

            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: const Text('ยืนยันส่งพัสดุ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===== โมเดลสินค้าในฟอร์ม (เก็บในหน่วยความจำ) =====
class _ItemRow {
  _ItemRow();
  final String id = UniqueKey().toString();
  String name = '';
  int qty = 1;
  double? weight;
  String? note;

  Map<String, dynamic> toMap() => {
    'name': name.trim(),
    'qty': qty,
    'weight': weight,
    'note': note?.trim(),
  };
}

/// ===== การ์ด UI ของแต่ละสินค้า =====
class _ItemCard extends StatefulWidget {
  const _ItemCard({required this.item, this.onRemove, super.key});

  final _ItemRow item;
  final VoidCallback? onRemove;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  final _nameCtl = TextEditingController();
  final _qtyCtl = TextEditingController(text: '1');
  final _weightCtl = TextEditingController();
  final _noteCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtl.text = widget.item.name;
    _qtyCtl.text = widget.item.qty.toString();
    _weightCtl.text = widget.item.weight?.toString() ?? '';
    _noteCtl.text = widget.item.note ?? '';
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
      ..note = _noteCtl.text.isNotEmpty ? _noteCtl.text : null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _nameCtl,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อสินค้า',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
                const SizedBox(width: 8),
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
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'น้ำหนัก (เช่น กก.)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _noteCtl,
                    decoration: const InputDecoration(
                      labelText: 'หมายเหตุ (ถ้ามี)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _sync(),
                  ),
                ),
              ],
            ),
            if (widget.onRemove != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('ลบรายการนี้'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 🎯 ไฟล์: lib/pages/sendpage.dart (ฉบับอัปเดต)

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class SendPage extends StatefulWidget {
  final String? senderPhone;
  const SendPage({super.key, this.senderPhone});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  static const String RECEIVER_COLLECTION = 'user';
  final _formKey = GlobalKey<FormState>();

  final _receiverPhoneCtl = TextEditingController();

  bool _loadingReceiver = false;
  Map<String, dynamic>? _receiverDoc;
  List<Map<String, dynamic>> _receiverAddresses = [];
  Map<String, dynamic>? _selectedReceiverAddress;

  final List<_ItemRow> _items = [_ItemRow()];
  bool _submitting = false;

  final ImagePicker _picker = ImagePicker();

  void _resetForm() {
    setState(() {
      _receiverPhoneCtl.clear();
      _receiverDoc = null;
      _receiverAddresses = [];
      _selectedReceiverAddress = null;
      _items.clear();
      _items.add(_ItemRow());
      _submitting = false;
    });
  }

  @override
  void dispose() {
    _receiverPhoneCtl.dispose();
    super.dispose();
  }

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
          '${folder}/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
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

    if (_receiverDoc == null || _selectedReceiverAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกผู้รับและที่อยู่ให้ครบถ้วน')),
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
      List<Map<String, dynamic>> itemsForPayload = [];
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

      String senderName = '';
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('user')
            .doc(senderPhone)
            .get();
        if (userDoc.exists) {
          senderName = userDoc.data()?['name'] as String? ?? '';
        }
      } catch (e) {
        log("ไม่สามารถค้นหาชื่อผู้ส่งได้: $e");
      }

      final receiverPhone = _receiverDoc!['phone'] as String;
      final receiverName = (_receiverDoc!['name'] ?? '') as String? ?? '';
      final addr = _selectedReceiverAddress!;
      final receiverAddr = {
        'address': addr['address'] ?? '',
        'lat': (addr['lat'] as num?)?.toDouble(),
        'lng': (addr['lng'] as num?)?.toDouble(),
      };

      final payload = {
        'senderId': senderPhone,
        'senderName': senderName,
        'receiverId': receiverPhone,
        'receiverName': receiverName,
        'receiverPhone': receiverPhone,
        'receiverAddress': receiverAddr,
        'items': itemsForPayload,
        'status': 'created',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('deliveries').add(payload);

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
              child: Center(child: Text(widget.senderPhone!)),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
                  picker: _picker,
                  onRemove: _items.length > 1
                      ? () => _removeItemRow(index)
                      : null,
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
    final file = await widget.picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (file != null) {
      setState(() {
        _pickedImage = file;
        _sync();
      });
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

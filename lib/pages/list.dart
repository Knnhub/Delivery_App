// 🎯 lib/pages/list.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'deliveries_map.dart';

class listPage extends StatefulWidget {
  const listPage({super.key, this.senderPhone});

  /// เบอร์ผู้ส่ง (ผู้ใช้ปัจจุบัน) ใช้เป็นเงื่อนไขค้นหา
  final String? senderPhone;

  @override
  State<listPage> createState() => _listPageState();
}

class _listPageState extends State<listPage> {
  @override
  Widget build(BuildContext context) {
    final phone = widget.senderPhone?.trim();
    if (phone == null || phone.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('พัสดุของฉัน')),
        body: const Center(child: Text('ไม่พบหมายเลขผู้ส่ง (senderPhone)')),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('deliveries')
        .where('senderId', isEqualTo: phone)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      // --- ✨ แก้ไข AppBar ตรงนี้ ---
      appBar: AppBar(
        title: const Text('พัสดุของฉัน'),
        actions: [
          // --- 👇 เพิ่ม IconButton สำหรับเปิดแผนที่ 👇 ---
          IconButton(
            tooltip: 'ดูตำแหน่งปลายทางทั้งหมดบนแผนที่',
            icon: const Icon(Icons.map_outlined), // ไอคอนแผนที่
            onPressed: () {
              // เช็คว่ามี phone ก่อน Navigator.push
              if (phone != null && phone.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // ไปยัง DeliveriesMapPage และส่ง senderPhone
                    builder: (_) => DeliveriesMapPage(senderPhone: phone),
                  ),
                );
              } else {
                // แสดง SnackBar ถ้าไม่มี phone (ควรจะไม่เกิดเพราะมีการเช็คด้านบนแล้ว)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ไม่พบหมายเลขผู้ส่ง')),
                );
              }
            },
          ),
          // --- จบ IconButton แผนที่ ---

          // IconButton ประวัติ (ที่มีอยู่เดิม)
          // IconButton(
          //   tooltip: 'ประวัติการจัดส่ง',
          //   icon: const Icon(
          //     Icons.history_outlined,
          //   ), // เปลี่ยนไอคอนเล็กน้อย (Optional)
          //   onPressed: () {
          //     if (phone != null && phone.isNotEmpty) {
          //       // เช็ค phone ก่อน push
          //       Navigator.push(
          //         context,
          //         MaterialPageRoute(
          //           builder: (_) => SenderHistoryPage(senderPhone: phone),
          //         ),
          //       );
          //     }
          //   },
          // ),
        ],
      ),
      // --- จบการแก้ไข AppBar ---
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            // แสดง Error ที่ละเอียดขึ้น ถ้าเป็น FAILED_PRECONDITION (Missing Index)
            if (snap.error.toString().contains('FAILED_PRECONDITION')) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Firestore index required. Please create the index in Firebase Console: ${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีพัสดุที่คุณสร้าง'));
          }

          // --- ส่วน ListView.separated เหมือนเดิม ---
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              // ... (ดึงข้อมูล receiverName, receiverPhone, etc. เหมือนเดิม) ...
              final receiverName = (data['receiverName'] as String?) ?? '';
              final receiverPhone = (data['receiverPhone'] as String?) ?? '';
              final addr =
                  (data['receiverAddress'] ?? {}) as Map<String, dynamic>;
              final addressText = (addr['address'] as String?) ?? '';
              final lat = (addr['lat'] as num?)?.toDouble();
              final lng = (addr['lng'] as num?)?.toDouble();
              final status = (data['status'] ?? 'created') as String;
              final ts = data['createdAt'];
              DateTime? createdAt;
              if (ts is Timestamp) createdAt = ts.toDate();

              return Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  leading: _statusThumb(data),
                  title: Text(
                    receiverName.isNotEmpty ? receiverName : receiverPhone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (addressText.isNotEmpty)
                        Text(
                          addressText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (lat != null && lng != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'พิกัดผู้รับ: (${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _formatCreatedAt(createdAt),
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  trailing: _StatusChip(status: status),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            _DeliveryDetailPage(docId: docs[i].id, data: data),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatCreatedAt(DateTime? dt) {
    if (dt == null) return 'กำลังสร้าง…';
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return 'สร้างเมื่อ $dd/$m/$y $hh:$mm';
  }
}

/// รูปย่ออิงสถานะ: delivered => delivery proof, picked => pickup proof, อื่น ๆ => รูปสินค้าชิ้นแรก
Widget _statusThumb(Map<String, dynamic> data) {
  final status = (data['status'] as String?) ?? 'created';
  String? url;

  if (status == 'delivered') {
    url = data['deliveryProofImageUrl'] as String?;
  } else if (status == 'picked') {
    url = data['pickupProofImageUrl'] as String?;
  }

  // fallback: รูปสินค้าชิ้นแรก
  if ((url == null || url.isEmpty) &&
      data['items'] is List &&
      (data['items'] as List).isNotEmpty) {
    final first = (data['items'] as List).first;
    if (first is Map && first['imageUrl'] is String) {
      url = first['imageUrl'] as String?;
    }
  }

  if (url == null || url.isEmpty) {
    return const CircleAvatar(child: Icon(Icons.inventory_2_outlined));
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Image.network(
      url,
      width: 40,
      height: 40,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const CircleAvatar(child: Icon(Icons.image_not_supported)),
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : const SizedBox(
              width: 40,
              height: 40,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  Color _bg() {
    switch (status) {
      case 'created':
        return Colors.blue.shade50;
      case 'assigned':
        return Colors.orange.shade50;
      case 'picked':
        return Colors.amber.shade50;
      case 'delivered':
        return Colors.green.shade50;
      case 'canceled':
        return Colors.red.shade50;
      default:
        return Colors.grey.shade200;
    }
  }

  Color _fg() {
    switch (status) {
      case 'created':
        return Colors.blue.shade700;
      case 'assigned':
        return Colors.orange.shade800;
      case 'picked':
        return Colors.amber.shade800;
      case 'delivered':
        return Colors.green.shade800;
      case 'canceled':
        return Colors.red.shade800;
      default:
        return Colors.grey.shade800;
    }
  }

  String _label() {
    switch (status) {
      case 'created':
        return 'รอไรเดอร์มารับสินค้า';
      case 'assigned':
        return 'ไรเดอร์รับงาน';
      case 'picked':
        return 'กำลังเดินทางไปส่ง';
      case 'delivered':
        return 'ส่งสำเร็จ';
      case 'canceled':
        return 'ยกเลิก';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label(),
        style: TextStyle(color: _fg(), fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// หน้าแสดงรายละเอียด (พิกัด + เปิดแผนที่ + รูปหลักฐาน pickup/delivery + รูปสินค้าตามรายการ)
class _DeliveryDetailPage extends StatelessWidget {
  const _DeliveryDetailPage({required this.docId, required this.data});
  final String docId;
  final Map<String, dynamic> data;

  Future<void> _openInMaps({
    required BuildContext context,
    required double lat,
    required double lng,
    String? label,
  }) async {
    final encodedLabel = Uri.encodeComponent(label ?? 'ตำแหน่ง');
    final web = Uri.parse(
      'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=66bb35dc3aad4f21b4b0de85b001cb0a',
    );
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encodedLabel)');

    try {
      final ok = await launchUrl(web, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่สามารถเปิดแผนที่ได้')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List?)?.cast<Map>() ?? const [];
    final senderAddr = (data['senderAddress'] ?? {}) as Map<String, dynamic>;
    final recvAddr = (data['receiverAddress'] ?? {}) as Map<String, dynamic>;

    final sLat = (senderAddr['lat'] as num?)?.toDouble();
    final sLng = (senderAddr['lng'] as num?)?.toDouble();
    final rLat = (recvAddr['lat'] as num?)?.toDouble();
    final rLng = (recvAddr['lng'] as num?)?.toDouble();

    final pickupProof = (data['pickupProofImageUrl'] as String?) ?? '';
    final deliveryProof = (data['deliveryProofImageUrl'] as String?) ?? '';
    final assignedAt = (data['assignedAt'] as Timestamp?)?.toDate();
    final pickedAt = (data['pickedAt'] as Timestamp?)?.toDate();
    final deliveredAt = (data['deliveredAt'] as Timestamp?)?.toDate();

    return Scaffold(
      appBar: AppBar(
        title: Text('รายละเอียดพัสดุ #${docId.substring(0, 6)}...'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ข้อมูลผู้ส่ง
          Card(
            elevation: 0.5,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ข้อมูลผู้ส่ง',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _iconLine(
                    Icons.person_outline,
                    '${data['senderName'] ?? ''} (${data['senderId'] ?? ''})',
                  ),
                  const SizedBox(height: 6),
                  _iconLine(
                    Icons.place_outlined,
                    senderAddr['address'] as String? ?? '-',
                  ),
                  if (sLat != null && sLng != null) ...[
                    const SizedBox(height: 6),
                    _coordsLine(
                      context,
                      sLat,
                      sLng,
                      label: 'พิกัดผู้ส่ง',
                      icon: Icons.map,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ข้อมูลผู้รับ
          Card(
            elevation: 0.5,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ข้อมูลผู้รับ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _iconLine(
                    Icons.person_pin_circle_outlined,
                    '${data['receiverName'] ?? ''} (${data['receiverPhone'] ?? ''})',
                  ),
                  const SizedBox(height: 6),
                  _iconLine(
                    Icons.place_outlined,
                    recvAddr['address'] as String? ?? '-',
                  ),
                  if (rLat != null && rLng != null) ...[
                    const SizedBox(height: 6),
                    _coordsLine(
                      context,
                      rLat,
                      rLng,
                      label: 'พิกัดผู้รับ',
                      icon: Icons.map_outlined,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // รายการสินค้า
          Card(
            elevation: 0.5,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'รายการสินค้า (${items.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...items.map((itemData) {
                    final imageUrl = itemData['imageUrl'] as String?;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrl,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const SizedBox(
                                    height: 180,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                      height: 180,
                                      color: Colors.grey.shade200,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.broken_image,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${itemData['name'] ?? '-'}'),
                          subtitle: Text(
                            'จำนวน: ${itemData['qty'] ?? '-'}'
                            '${itemData['weight'] != null ? ' • น้ำหนัก: ${itemData['weight']} กก.' : ''}'
                            '${(itemData['note'] ?? '').toString().isNotEmpty ? '\nหมายเหตุ: ${itemData['note']}' : ''}',
                          ),
                        ),
                        const Divider(height: 16),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),

          // หลักฐานการจัดส่ง (รูปตามสถานะ)
          if (pickupProof.isNotEmpty || deliveryProof.isNotEmpty)
            Card(
              elevation: 0.5,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'หลักฐานการจัดส่ง',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (assignedAt != null)
                      _iconLine(
                        Icons.assignment_turned_in_outlined,
                        'มอบหมายงาน: $assignedAt',
                      ),
                    if (pickedAt != null)
                      _iconLine(Icons.inbox_outlined, 'รับของแล้ว: $pickedAt'),
                    if (deliveredAt != null)
                      _iconLine(
                        Icons.check_circle_outline,
                        'ส่งสำเร็จ: $deliveredAt',
                      ),

                    if (pickupProof.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'หลักฐานการรับของ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _ProofFullWidth(url: pickupProof),
                    ],
                    if (deliveryProof.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'หลักฐานการส่งของ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      _ProofFullWidth(url: deliveryProof),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: Colors.black54),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ],
  );

  Widget _coordsLine(
    BuildContext context,
    double lat,
    double lng, {
    required String label,
    required IconData icon,
  }) => Row(
    children: [
      Icon(icon, size: 18, color: Colors.black54),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          '$label: (${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})',
          style: const TextStyle(color: Colors.black54),
        ),
      ),
      TextButton(
        onPressed: () =>
            _openInMaps(context: context, lat: lat, lng: lng, label: label),
        child: const Text('เปิดแผนที่'),
      ),
    ],
  );
}

/// แสดงรูปเต็มความกว้าง + คลิกดูแบบซูม
class _ProofFullWidth extends StatelessWidget {
  const _ProofFullWidth({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openViewer(context, url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: double.infinity,
          height: 220,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, __, ___) => Container(
            height: 220,
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Stack(
            children: [
              Positioned.fill(child: Image.network(url, fit: BoxFit.contain)),
              Positioned(
                right: 6,
                top: 6,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

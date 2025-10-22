import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class listPage extends StatefulWidget {
  const listPage({super.key, this.senderPhone});

  /// เบอร์โทรของผู้ส่ง (ผู้ใช้ปัจจุบัน) ใช้เป็นเงื่อนไขค้นหา
  final String? senderPhone;

  @override
  State<listPage> createState() => _listPageState();
}

class _listPageState extends State<listPage> {
  @override
  Widget build(BuildContext context) {
    if (widget.senderPhone == null || widget.senderPhone!.trim().isEmpty) {
      // ป้องกันกรณีไม่ได้ส่ง senderPhone มา
      return Scaffold(
        appBar: AppBar(title: Text('พัสดุของฉัน')),
        body: Center(child: Text('ไม่พบหมายเลขผู้ส่ง (senderPhone)')),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('deliveries')
        .where('senderId', isEqualTo: widget.senderPhone)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('พัสดุของฉัน')),
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีพัสดุที่คุณสร้าง'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final receiverName =
                  (data['receiverName'] ?? '') as String? ?? '';
              final receiverPhone =
                  (data['receiverPhone'] ?? '') as String? ?? '';
              final addr =
                  (data['receiverAddress'] ?? {}) as Map<String, dynamic>;
              final addressText = (addr['address'] ?? '') as String? ?? '';
              final items = (data['items'] as List?) ?? const [];
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
                  leading: CircleAvatar(child: Text(items.length.toString())),
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
    // ฟอร์แมตง่าย ๆ โดยไม่พึ่งแพ็กเกจเพิ่ม
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return 'สร้างเมื่อ $dd/$m/$y $hh:$mm';
  }
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

/// หน้าแสดงรายละเอียด (ตัวอย่างง่าย ๆ)
class _DeliveryDetailPage extends StatelessWidget {
  const _DeliveryDetailPage({required this.docId, required this.data});
  final String docId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List?)?.cast<Map>() ?? const [];
    final addr = (data['receiverAddress'] ?? {}) as Map<String, dynamic>;
    return Scaffold(
      appBar: AppBar(title: Text('รายละเอียดพัสดุ #$docId')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('ผู้รับ'),
            subtitle: Text(
              '${data['receiverName'] ?? ''} (${data['receiverPhone'] ?? ''})',
            ),
          ),
          ListTile(
            title: const Text('ที่อยู่ผู้รับ'),
            subtitle: Text(
              '${addr['address'] ?? '-'}'
              '${addr['lat'] != null ? '\n(${addr['lat']}, ${addr['lng']})' : ''}',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'รายการสินค้า',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...items.map((itemData) {
            final imageUrl = itemData['imageUrl'] as String?;

            return Card(
              clipBehavior: Clip.antiAlias,
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    Image.network(
                      imageUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          heightFactor: 4,
                          child: CircularProgressIndicator(),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          heightFactor: 4,
                          child: Icon(
                            Icons.broken_image,
                            size: 40,
                            color: Colors.grey,
                          ),
                        );
                      },
                    ),

                  ListTile(
                    title: Text('${itemData['name'] ?? '-'}'),
                    subtitle: Text(
                      'จำนวน: ${itemData['qty'] ?? '-'}'
                      '${itemData['weight'] != null ? ' • น้ำหนัก: ${itemData['weight']} กก.' : ''}'
                      '${(itemData['note'] ?? '').toString().isNotEmpty ? '\nหมายเหตุ: ${itemData['note']}' : ''}',
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

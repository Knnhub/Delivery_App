import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'tracking_map_page.dart';

class ReceivePage extends StatefulWidget {
  // รับเบอร์โทรผู้ใช้ปัจจุบันจาก UserhomePage
  final String? currentUserPhone;
  const ReceivePage({super.key, this.currentUserPhone});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  @override
  Widget build(BuildContext context) {
    // ✅ ตรวจสอบเบอร์โทรของผู้ใช้ก่อน
    final phone = widget.currentUserPhone?.trim();
    if (phone == null || phone.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('พัสดุถึงฉัน')),
        body: const Center(child: Text('ไม่พบหมายเลขผู้ใช้ปัจจุบัน')),
      );
    }

    // ✅ Query หาเอกสารที่ส่งถึงผู้ใช้คนนี้
    final q = FirebaseFirestore.instance
        .collection('deliveries')
        .where('receiverPhone', isEqualTo: phone)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('พัสดุถึงฉัน')),
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            if (snap.error.toString().contains('FAILED_PRECONDITION')) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'ฐานข้อมูลต้องการ Index เพิ่มเติม โปรดไปที่ Firebase Console และสร้าง Index ตามที่ Error แนะนำใน Debug Console',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีพัสดุส่งถึงคุณ'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final senderName =
                  (data['senderName'] ?? 'ไม่มีชื่อผู้ส่ง') as String;
              final senderId = (data['senderId'] ?? 'ไม่ระบุผู้ส่ง') as String;
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
                    'จาก: ${senderName.isNotEmpty ? senderName : senderId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _formatCreatedAt(createdAt),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  trailing: _StatusChip(status: status),
                  onTap: () {
                    // ✅ ส่ง currentUserPhone ต่อไปยังหน้า detail เพื่อใช้เปิดแผนที่
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _DeliveryDetailPage(
                          docId: docs[i].id,
                          data: data,
                          currentUserPhone: widget.currentUserPhone,
                          // currentUserPhone: phone,
                        ),
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

  // แปลงวันที่
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

// --- UI แสดงสถานะพัสดุ ---
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
        return 'สร้างแล้ว';
      case 'assigned':
        return 'มอบหมายแล้ว';
      case 'picked':
        return 'รับของแล้ว';
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

// --- หน้าแสดงรายละเอียดพัสดุ + ปุ่มติดตาม ---
class _DeliveryDetailPage extends StatelessWidget {
  const _DeliveryDetailPage({
    required this.docId,
    required this.data,
    this.currentUserPhone, // รับมาจาก ReceivePage
  });
  final String docId;
  final Map<String, dynamic> data;
  final String? currentUserPhone;

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List?)?.cast<Map>() ?? const [];
    final addr = (data['receiverAddress'] ?? {}) as Map<String, dynamic>;
    final status = (data['status'] ?? 'unknown') as String;

    final phone = currentUserPhone?.trim();
    final canTrack =
        (status == 'assigned' || status == 'picked') &&
        (phone != null && phone.isNotEmpty);

    return Scaffold(
      appBar: AppBar(title: Text('หมายเลขพัสดุ #${docId.substring(0, 6)}...')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ปุ่มติดตามตำแหน่ง Rider (หลาย Rider ของผู้รับ)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: const Text('ติดตามตำแหน่ง Rider'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: canTrack
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TrackingMapPage(
                            receiverPhone:
                                phone!, // ปลอดภัยเพราะ canTrack เช็คแล้ว
                          ),
                        ),
                      );
                    }
                  : () {
                      // แจ้งเหตุผลทำไมกดไม่ได้ (ไม่มีสถานะหรือไม่มีเบอร์)
                      final reason = (phone == null || phone.isEmpty)
                          ? 'ไม่พบเบอร์ผู้รับ — เปิดแผนที่ไม่ได้'
                          : 'พัสดุยังไม่อยู่ในสถานะกำลังเดินทาง';
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(reason)));
                    },
            ),
          ),

          ListTile(
            title: const Text('ที่อยู่ผู้รับ'),
            subtitle: Text(
              '${addr['address'] ?? '-'}'
              '${addr['lat'] != null ? '\n(${addr['lat']}, ${addr['lng']})' : ''}',
            ),
          ),
          const Divider(height: 24),
          const Text(
            'รายการสินค้า',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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

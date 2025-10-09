import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
    //ส่วนตรวจสอบข้อมูล
    if (widget.currentUserPhone == null ||
        widget.currentUserPhone!.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('พัสดุถึงฉัน')),
        body: const Center(child: Text('ไม่พบหมายเลขผู้ใช้ปัจจุบัน')),
      );
    }

    // ส่วนสร้างคำสั่ง Query
    final q = FirebaseFirestore.instance
        .collection('deliveries')
        .where('receiverPhone', isEqualTo: widget.currentUserPhone)
        .orderBy('createdAt', descending: true);

    //ส่วนสร้้าง UI
    return Scaffold(
      appBar: AppBar(title: const Text('พัสดุถึงฉัน')),
      body: StreamBuilder<QuerySnapshot>(
        stream: q
            .snapshots(), // บอกให้ StreamBuilder ดักฟังข้อมูลจาก Query ของเรา
        builder: (context, snap) {
          //  ส่วนที่จะสร้าง UI ตามสถานะของข้อมูล
          // จัดการสถานะต่างๆ ของข้อมูล
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            // ถ้าเกิด Error
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
            // ถ้าไม่มีข้อมูล...
            return const Center(child: Text('ยังไม่มีพัสดุส่งถึงคุณ'));
          }

          // --- ✅ ส่วนที่แก้ไข: เปลี่ยนมาใช้ ListView ---
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
                    'จาก: ${senderName.isNotEmpty ? senderName : senderId}', // แสดงเบอร์ผู้ส่ง
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _formatCreatedAt(createdAt),
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
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
          // --- จบส่วนแก้ไข ---
        },
      ),
    );
  }

  //ฟังชันแปลงวันที่
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

// --- ✨ Widget ย่อยที่คัดลอกมาจาก list.dart ---

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

class _DeliveryDetailPage extends StatelessWidget {
  const _DeliveryDetailPage({required this.docId, required this.data});
  final String docId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List?)?.cast<Map>() ?? const [];
    final addr = (data['receiverAddress'] ?? {}) as Map<String, dynamic>;
    return Scaffold(
      appBar: AppBar(title: Text('หมายเลขพัสดุ #$docId')),
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
          ...items.map(
            (m) => Card(
              child: ListTile(
                title: Text('${m['name'] ?? '-'}'),
                subtitle: Text(
                  'จำนวน: ${m['qty'] ?? '-'}'
                  '${m['weight'] != null ? ' • น้ำหนัก: ${m['weight']}' : ''}'
                  '${(m['note'] ?? '').toString().isNotEmpty ? '\nหมายเหตุ: ${m['note']}' : ''}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

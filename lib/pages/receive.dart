import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'tracking_map_page.dart';

class ReceivePage extends StatefulWidget {
  final String? currentUserPhone;
  const ReceivePage({super.key, this.currentUserPhone});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  @override
  Widget build(BuildContext context) {
    final phone = widget.currentUserPhone?.trim();
    if (phone == null || phone.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('พัสดุถึงฉัน')),
        body: const Center(child: Text('ไม่พบหมายเลขผู้ใช้ปัจจุบัน')),
      );
    }

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
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'จำเป็นต้องสร้าง Firestore Index ก่อน ใช้ลิงก์ที่ขึ้นใน Debug Console เพื่อสร้าง Index',
                  textAlign: TextAlign.center,
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
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final code = (data['code'] as String?) ?? doc.id.substring(0, 6);
              final senderName =
                  (data['senderName'] as String?) ??
                  (data['senderId'] as String? ?? '-');
              final status = (data['status'] as String?) ?? 'created';
              final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

              return Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  title: Text(
                    'รายละเอียด #$code',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'จาก: $senderName\n${_formatCreatedAt(createdAt)}',
                    ),
                  ),
                  isThreeLine: true,
                  trailing: _StatusChip(status: status),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _DeliveryDetailPage(
                          docId: doc.id,
                          data: data,
                          currentUserPhone: phone,
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

/// ========================
/// Widgets ย่อย
/// ========================
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.trailing,
  });
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50.withOpacity(0.3),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _IconRow extends StatelessWidget {
  const _IconRow({required this.icon, required this.label, this.bold = false});
  final IconData icon;
  final String label;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.green.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DividerThin extends StatelessWidget {
  const _DividerThin();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 16, thickness: 0.6);
}

/// ========================
/// รายละเอียดพัสดุ (สไตล์ตามภาพตัวอย่าง)
/// ========================
class _DeliveryDetailPage extends StatelessWidget {
  const _DeliveryDetailPage({
    required this.docId,
    required this.data,
    this.currentUserPhone,
  });

  final String docId;
  final Map<String, dynamic> data;
  final String? currentUserPhone;

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  List<String> _proofUrlsFrom(Map<String, dynamic> m, String field) {
    final v = m[field];
    final urls = <String>[];
    if (v is String && v.trim().isNotEmpty) urls.add(v.trim());
    if (v is List) {
      for (final e in v) {
        if (e is String && e.trim().isNotEmpty) urls.add(e.trim());
        if (e is Map &&
            e['url'] is String &&
            (e['url'] as String).trim().isNotEmpty) {
          urls.add((e['url'] as String).trim());
        }
      }
    }
    return urls;
  }

  @override
  Widget build(BuildContext context) {
    final senderAddr = (data['senderAddress'] as Map<String, dynamic>?) ?? {};
    final receiverAddr =
        (data['receiverAddress'] as Map<String, dynamic>?) ?? {};
    final status = (data['status'] as String?) ?? 'unknown';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final assignedAt = (data['assignedAt'] as Timestamp?)?.toDate();
    final pickedAt = (data['pickedAt'] as Timestamp?)?.toDate();
    final deliveredAt = (data['deliveredAt'] as Timestamp?)?.toDate();
    final items = (data['items'] as List?)?.cast<Map>() ?? const [];

    // หลักฐาน (รองรับหลากหลายชื่อฟิลด์)
    final receiveProofs = <String>[
      ..._proofUrlsFrom(data, 'pickupProofImageUrl'),
      ..._proofUrlsFrom(data, 'pickupProofImageUrl'),
      ..._proofUrlsFrom(data, 'pickupProofImageUrl'),
    ].toSet().toList();

    final deliverProofs = <String>[
      ..._proofUrlsFrom(data, 'deliveryProofImageUrl'),
      ..._proofUrlsFrom(data, 'deliveryProofImageUrl'),
      ..._proofUrlsFrom(
        data,
        'deliveryProofImageUrl',
      ), // เผื่อเก็บไว้ฟิลด์เดียว
    ].toSet().toList();

    final canTrack =
        (status == 'assigned' || status == 'picked') &&
        (currentUserPhone != null && currentUserPhone!.isNotEmpty);

    final code = (data['code'] as String?) ?? docId.substring(0, 6);

    return Scaffold(
      appBar: AppBar(
        title: Text('รายละเอียด #$code'),
        actions: [
          if (status == 'delivered')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Text(
                  'ส่งสำเร็จ',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ปุ่มติดตามตำแหน่ง
          _SectionCard(
            title: 'สถานะพัสดุ',
            trailing: _StatusChip(status: status),
            children: [
              _IconRow(
                icon: Icons.schedule_outlined,
                label: 'สร้างเมื่อ: ${_fmt(createdAt)}',
              ),
              if (assignedAt != null)
                _IconRow(
                  icon: Icons.person_pin_circle_outlined,
                  label: 'มอบหมาย: ${_fmt(assignedAt)}',
                ),
              if (pickedAt != null)
                _IconRow(
                  icon: Icons.local_shipping_outlined,
                  label: 'รับของแล้ว: ${_fmt(pickedAt)}',
                ),
              if (deliveredAt != null)
                _IconRow(
                  icon: Icons.check_circle_outline,
                  label: 'ส่งสำเร็จเมื่อ: ${_fmt(deliveredAt)}',
                ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.map_outlined),
                label: const Text('ติดตามตำแหน่ง Rider'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                ),
                onPressed: canTrack
                    ? () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TrackingMapPage(
                              receiverPhone: currentUserPhone!,
                            ),
                          ),
                        );
                      }
                    : null,
              ),
            ],
          ),

          // ข้อมูลผู้ส่ง
          _SectionCard(
            title: 'ข้อมูลผู้ส่ง',
            children: [
              _IconRow(
                icon: Icons.person_outline,
                label: 'ชื่อผู้ส่ง\n${data['senderName'] ?? '-'}',
              ),
              _IconRow(
                icon: Icons.call_outlined,
                label: 'เบอร์โทรผู้ส่ง\n${data['senderId'] ?? '-'}',
              ),
              _IconRow(
                icon: Icons.place_outlined,
                label: 'ที่อยู่ผู้ส่ง\n${senderAddr['address'] ?? '-'}',
              ),
            ],
          ),

          // ข้อมูลผู้รับ
          _SectionCard(
            title: 'ข้อมูลผู้รับ',
            children: [
              _IconRow(
                icon: Icons.person_pin_outlined,
                label: 'ชื่อผู้รับ\n${data['receiverName'] ?? '-'}',
              ),
              _IconRow(
                icon: Icons.smartphone_outlined,
                label: 'เบอร์โทรผู้รับ\n${data['receiverPhone'] ?? '-'}',
              ),
              _IconRow(
                icon: Icons.place_outlined,
                label: 'ที่อยู่ผู้รับ\n${receiverAddr['address'] ?? '-'}',
              ),
            ],
          ),

          // รายการสินค้า
          _SectionCard(
            title: 'รายการสินค้า (${items.length})',
            children: [
              for (final it in items) ...[
                Text(
                  '${it['name'] ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'จำนวน: ${it['qty'] ?? '-'}'
                  '${it['weight'] != null ? ' • น้ำหนัก: ${it['weight']} กก.' : ''}'
                  '${(it['note'] ?? '').toString().isNotEmpty ? '\nหมายเหตุ: ${it['note']}' : ''}',
                ),
                const _DividerThin(),
              ],
              if (items.isEmpty) const Text('— ไม่มีรายการสินค้า —'),
            ],
          ),

          // ข้อมูลเวลา
          _SectionCard(
            title: 'ข้อมูลเวลา',
            children: [
              _IconRow(
                icon: Icons.schedule_outlined,
                label: 'สร้างเมื่อ: ${_fmt(createdAt)}',
              ),
              _IconRow(
                icon: Icons.person_pin_circle_outlined,
                label: 'มอบหมาย: ${_fmt(assignedAt)}',
              ),
              _IconRow(
                icon: Icons.local_shipping_outlined,
                label: 'รับของแล้ว: ${_fmt(pickedAt)}',
              ),
              _IconRow(
                icon: Icons.check_circle_outline,
                label: 'ส่งสำเร็จ: ${_fmt(deliveredAt)}',
              ),
            ],
          ),

          // หลักฐานการรับของ
          if (receiveProofs.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              'หลักฐานการรับของ',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final u in receiveProofs) _ProofFullWidth(url: u),
            const SizedBox(height: 16),
          ],

          // หลักฐานการส่งของ
          if (deliverProofs.isNotEmpty) ...[
            const Text(
              'หลักฐานการส่งของ',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final u in deliverProofs) _ProofFullWidth(url: u),
          ],
        ],
      ),
    );
  }
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

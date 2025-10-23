// 🎯 ไฟล์ใหม่: lib/pages/rider_detail_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:developer';
import 'tracking_map_page.dart';

class RiderDetailPage extends StatefulWidget {
  final String riderId; // รับ Rider ID (ซึ่งคือเบอร์โทร)

  const RiderDetailPage({super.key, required this.riderId});

  @override
  State<RiderDetailPage> createState() => _RiderDetailPageState();
}

class _RiderDetailPageState extends State<RiderDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _riderData;
  String? _errorMsg;
  var db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchRiderData();
  }

  // 🎯 ไฟล์: lib/pages/rider_detail_page.dart (แก้ไข _fetchRiderData)

  Future<void> _fetchRiderData() async {
    log('[RiderDetail] Fetching data for riderId: ${widget.riderId}');
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    DocumentSnapshot? doc;
    // --- ✨ 1. แก้ไข: เริ่มต้นด้วย 'user' ---
    String foundInCollection = 'user'; // ลองหาใน 'user' ก่อน

    try {
      // --- ✨ 2. แก้ไข: ค้นหาใน 'user' ก่อน ---
      log('[RiderDetail] Trying collection: user');
      doc = await db.collection('user').doc(widget.riderId).get();

      // --- ✨ 3. ถ้าไม่เจอใน 'user' ค่อยลอง 'rider' ---
      if (!doc.exists) {
        log('[RiderDetail] Not found in "user". Trying collection: rider');
        foundInCollection = 'rider'; // เปลี่ยนเป็น 'rider'
        doc = await db
            .collection('rider')
            .doc(widget.riderId)
            .get(); // ค้นหาใน 'rider'
      }

      // --- ส่วนที่เหลือเหมือนเดิม ---
      if (doc.exists && mounted) {
        log('[RiderDetail] Data found in collection: $foundInCollection');
        setState(() {
          _riderData = doc!.data() as Map<String, dynamic>?;
          _isLoading = false;
        });
      } else if (mounted) {
        log('[RiderDetail] Rider data NOT found for ID: ${widget.riderId}');
        setState(() {
          _errorMsg = 'ไม่พบข้อมูล Rider';
          _isLoading = false;
        });
      }
    } catch (e) {
      log("[RiderDetail] Error fetching rider data: $e");
      if (mounted) {
        setState(() {
          _errorMsg = 'เกิดข้อผิดพลาด: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

    if (_isLoading) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else if (_errorMsg != null) {
      bodyContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
        ),
      );
    } else if (_riderData == null) {
      // ควรจะถูกดักโดย _errorMsg แล้ว แต่ใส่เผื่อไว้
      bodyContent = const Center(child: Text('ไม่พบข้อมูล Rider'));
    } else {
      // --- แสดงข้อมูล Rider ---
      final profileImageUrl = _riderData?['profilePicURL'] as String?;
      final name = _riderData?['name'] ?? 'ไม่มีชื่อ';
      final phone = widget.riderId; // ใช้ ID ที่ส่งมาเป็นเบอร์โทร
      final licensePlate = _riderData?['vehicleLicensePlate'] ?? '-';
      final vehiclePicUrl = _riderData?['vehiclePicUrl'] as String?;

      bodyContent = ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey.shade300,
              backgroundImage:
                  (profileImageUrl != null && profileImageUrl.isNotEmpty)
                  ? NetworkImage(profileImageUrl)
                  : null,
              child: (profileImageUrl == null || profileImageUrl.isEmpty)
                  ? const Icon(Icons.person, size: 50, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('ชื่อ Rider'),
            subtitle: Text(
              name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.phone),
            title: const Text('เบอร์โทรศัพท์'),
            subtitle: Text(
              phone,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('ทะเบียนรถ'),
            subtitle: Text(
              licensePlate,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (vehiclePicUrl != null && vehiclePicUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('รูปรถ:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                vehiclePicUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ],
          // สามารถเพิ่มข้อมูลอื่นๆ ของ Rider ได้ตามต้องการ
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('ข้อมูล Rider ${widget.riderId}')),
      body: bodyContent,
    );
  }
}

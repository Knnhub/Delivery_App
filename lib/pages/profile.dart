// 🎯 ไฟล์: lib/pages/profile_page.dart (ฉบับแก้ไขสมบูรณ์)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  final String? currentUserPhone;
  const ProfilePage({super.key, this.currentUserPhone});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  var db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    if (widget.currentUserPhone == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await db
          .collection('user')
          .doc(widget.currentUserPhone!)
          .get();

      if (doc.exists) {
        setState(() {
          _userData = doc.data();
        });
      }
    } catch (e) {
      print("Error fetching user data: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _logout() {
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('โปรไฟล์'),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userData == null
          ? const Center(child: Text('ไม่พบข้อมูลผู้ใช้'))
          : _buildProfileView(),
    );
  }

  Widget _buildProfileView() {
    // ✨ FIX: แก้ไขชื่อ field ให้ตรงกับใน Firestore
    final profileImageUrl = _userData?['profilePicURL'] as String?;
    final addresses = (_userData?['addresses'] as List<dynamic>? ?? []);

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        // --- ส่วนข้อมูลเดิม ---
        Center(
          child: CircleAvatar(
            radius: 60,
            backgroundColor: Colors.grey.shade300,
            backgroundImage:
                (profileImageUrl != null && profileImageUrl.isNotEmpty)
                ? NetworkImage(profileImageUrl)
                : null,
            child: (profileImageUrl == null || profileImageUrl.isEmpty)
                ? const Icon(Icons.person, size: 60, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('ชื่อ'),
            subtitle: Text(
              _userData?['name'] ?? 'ไม่มีข้อมูล',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: const Text('เบอร์โทรศัพท์'),
            subtitle: Text(
              widget.currentUserPhone ?? 'ไม่มีข้อมูล',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('ประเภทผู้ใช้'),
            subtitle: Text(
              _userData?['role'] ?? 'ไม่มีข้อมูล',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 12),

        // ✨ UPDATE: 2. ส่วนแสดงผลที่อยู่
        Text(
          'ที่อยู่ที่บันทึกไว้',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),

        // ถ้าไม่มีที่อยู่ ให้แสดงข้อความ
        if (addresses.isEmpty)
          const Text('ยังไม่มีที่อยู่ที่บันทึกไว้')
        // ถ้ามีที่อยู่ ให้วนลูปสร้าง Card
        else
          ...addresses.map((addr) {
            final addressMap = addr as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text(
                  addressMap['address'] ?? 'ไม่มีข้อมูลที่อยู่',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            );
          }).toList(),

        const SizedBox(height: 48), // เพิ่มระยะห่างก่อนปุ่ม Logout
        // ปุ่มออกจากระบบ
        ElevatedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('ออกจากระบบ'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

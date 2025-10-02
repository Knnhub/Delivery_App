import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class RiderhomePage extends StatefulWidget {
  const RiderhomePage({super.key});

  @override
  State<RiderhomePage> createState() => _RiderhomePageState();
}

class _RiderhomePageState extends State<RiderhomePage> {
  int _selectedIndex = 0;
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  String? _profilePicUrl;

  static const List<Widget> _pages = <Widget>[
    Center(child: Text('List Page')),
    Center(child: Text('Map Page')),
    Center(child: Text('History Page')),
    Center(child: Text('Logout Page')),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 3) {
      // Logout action
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rider Home')),
      body: _pages.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'List'),
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'Logout'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  Future<Map<String, dynamic>> _getCloudinarySignature() async {
    final res = await http.post(
      Uri.parse("https://<YOUR-API-DOMAIN>/cloudinary/sign"),
      body: {
        "timestamp": (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      },
    );
    if (res.statusCode != 200) {
      throw Exception("Sign failed: ${res.body}");
    }
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  Future<String?> _uploadProfileImage({required String phone}) async {
    if (_pickedImage == null) return null;

    try {
      const cloudName = "drskwb4o3"; // 👈 ของคุณ
      const uploadPreset = "images"; // 👈 ตั้งค่าไว้ใน Cloudinary

      final url = Uri.parse(
        "https://api.cloudinary.com/v1_1/$cloudName/image/upload",
      );

      // public_id เอาไว้ตั้งชื่อไฟล์ (optional)
      final publicId = "profiles/$phone";

      var request = http.MultipartRequest("POST", url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] =
            "images" // 👈 เก็บในโฟลเดอร์ images
        ..fields['public_id'] = publicId
        ..files.add(
          await http.MultipartFile.fromPath('file', _pickedImage!.path),
        );

      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        var jsonData = jsonDecode(responseData);
        return jsonData['secure_url']; // ✅ ได้ URL กลับมา
      } else {
        throw Exception("Upload failed: $responseData");
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
      return null;
    }
  }
}

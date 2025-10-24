import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Controllers
  final phoneCtl = TextEditingController();
  final passwordCtl = TextEditingController();
  final nameCtl = TextEditingController();
  final addressCtl = TextEditingController();
  final vehicleLicensePlateCtl = TextEditingController();

  // Role selection
  String role = 'user'; // 'user' | 'rider'

  // Firestore
  final db = FirebaseFirestore.instance;

  // Image Picker
  final ImagePicker _picker = ImagePicker();
  XFile? _pickedImage;
  XFile? _vehicleImage;
  String? _profilePicUrl; // หลังอัปโหลดเสร็จ จะได้ลิงก์มาบันทึกลง Firestore
  String? _vehiclePicUrl;

  // Map state
  final MapController _mapController = MapController();
  LatLng _center = LatLng(13.736717, 100.523186); // Bangkok default
  LatLng? _selectedLatLng;

  // Multiple addresses
  final List<Map<String, dynamic>> _addresses = [];

  bool _submitting = false;
  bool _reverseGeocoding = false;
  bool _obscure = true;

  @override
  void dispose() {
    phoneCtl.dispose();
    passwordCtl.dispose();
    nameCtl.dispose();
    addressCtl.dispose();
    vehicleLicensePlateCtl.dispose();
    super.dispose();
  }

  String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ================= Image helpers =================
  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังรูป'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('ถ่ายรูปใหม่'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file != null) {
      setState(() => _pickedImage = file);
    }
  }

  Future<void> _pickVehicleImage() async {
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังรูป'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('ถ่ายรูปใหม่'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file != null) {
      setState(() => _vehicleImage = file);
    }
  }

  Future<String?> _uploadProfileImage({required String phone}) async {
    if (_pickedImage == null) return null;

    try {
      const cloudName = 'drskwb4o3'; // ← ของคุณ
      const uploadPreset = 'images'; // ← preset ที่โชว์ในรูป
      const folder = 'images'; // ← โฟลเดอร์ปลายทาง

      final publicId =
          'profiles/${phone}_${DateTime.now().millisecondsSinceEpoch}';

      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      final req = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] =
            uploadPreset // ใช้ unsigned preset
        ..fields['folder'] = folder
        ..fields['public_id'] = publicId
        ..files.add(
          await http.MultipartFile.fromPath('file', _pickedImage!.path),
        );

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return json['secure_url'] as String?;
      } else {
        debugPrint('Cloudinary upload error ${res.statusCode}: $body');
        throw Exception('Upload failed');
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
      return null;
    }
  }

  Future<String?> _uploadVehicleImage({required String phone}) async {
    if (_vehicleImage == null) return null;

    try {
      const cloudName = 'drskwb4o3';
      const uploadPreset = 'images';
      const folder = 'images';

      final publicId =
          'vehicles/${phone}_${DateTime.now().millisecondsSinceEpoch}';

      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      final req = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = folder
        ..fields['public_id'] = publicId
        ..files.add(
          await http.MultipartFile.fromPath('file', _vehicleImage!.path),
        );

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return json['secure_url'] as String?;
      } else {
        debugPrint('Cloudinary upload error ${res.statusCode}: $body');
        throw Exception('Upload failed');
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อัปโหลดรูปภาพรถไม่สำเร็จ: $e')));
      return null;
    }
  }

  // ================= Geocode helpers =================
  Future<void> _geocodeAddress() async {
    final addr = addressCtl.text.trim();
    if (addr.isEmpty) return;
    try {
      final results = await geo.locationFromAddress(addr);
      if (results.isNotEmpty) {
        final r = results.first;
        final pos = LatLng(r.latitude, r.longitude);
        setState(() {
          _selectedLatLng = pos;
          _center = pos;
        });
        _mapController.move(pos, 15);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('หาตำแหน่งจากที่อยู่ไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    setState(() => _reverseGeocoding = true);
    try {
      final places = await geo.placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
        localeIdentifier: 'th_TH',
      );
      String fallback =
          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      if (places.isNotEmpty) {
        final p = places.first;
        final parts =
            [
                  p.name,
                  p.street,
                  p.subLocality,
                  p.locality,
                  p.administrativeArea,
                  p.postalCode,
                ]
                .where((e) => (e ?? '').trim().isNotEmpty)
                .map((e) => e!.trim())
                .toList();
        final label = parts.isEmpty ? fallback : parts.join(' ');
        setState(() {
          _selectedLatLng = pos;
          addressCtl.text = label;
        });
      } else {
        setState(() {
          _selectedLatLng = pos;
          addressCtl.text = fallback;
        });
      }
    } catch (e) {
      setState(() {
        _selectedLatLng = pos;
        addressCtl.text =
            '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      });
    } finally {
      if (mounted) setState(() => _reverseGeocoding = false);
    }
  }

  void _addCurrentAddress() {
    if (_selectedLatLng == null && addressCtl.text.trim().isEmpty) return;
    final item = {
      'address': addressCtl.text.trim(),
      'lat': _selectedLatLng?.latitude,
      'lng': _selectedLatLng?.longitude,
      'createdAt':
          DateTime.timestamp(), // Use server timestamp if possible: FieldValue.serverTimestamp()
    };
    setState(() {
      _addresses.add(item);
      addressCtl.clear();
      _selectedLatLng = null;
    });
  }

  Future<void> register() async {
    if (phoneCtl.text.trim().isEmpty ||
        passwordCtl.text.isEmpty ||
        nameCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรอกข้อมูลให้ครบถ้วน')));
      return;
    }
    // Add validation for Rider specific fields
    if (role == 'rider' && vehicleLicensePlateCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณากรอกทะเบียนรถ')));
      return;
    }
    // Optional: Add validation for images
    // if (_pickedImage == null) { ... }
    // if (role == 'rider' && _vehicleImage == null) { ... }

    setState(() => _submitting = true);
    try {
      final phone = phoneCtl.text.trim();

      // Check if phone number already exists
      final userExists = await db.collection('user').doc(phone).get();
      final riderExists = await db.collection('rider').doc(phone).get();

      if (userExists.exists || riderExists.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เบอร์โทรศัพท์นี้ถูกใช้งานแล้ว')),
        );
        setState(() => _submitting = false);
        return;
      }

      // อัปโหลดรูปโปรไฟล์ (ถ้ามี)
      _profilePicUrl = await _uploadProfileImage(phone: phone);

      // อัปโหลดรูปรถ (ถ้าเป็นไรเดอร์)
      if (role == 'rider') {
        _vehiclePicUrl = await _uploadVehicleImage(phone: phone);
      }

      final data = <String, dynamic>{
        'phone': phone, // Consider removing this if doc ID is the phone
        'passwordHash': hashPassword(passwordCtl.text),
        'name': nameCtl.text.trim(),
        'role': role,
        'profilePicUrl': _profilePicUrl, // Corrected field name
        'createdAt': FieldValue.serverTimestamp(), // Use server timestamp
      };

      if (role == 'user') {
        data['addresses'] = _addresses;
      } else if (role == 'rider') {
        data['vehicleLicensePlate'] = vehicleLicensePlateCtl.text.trim();
        data['vehiclePicUrl'] = _vehiclePicUrl; // Corrected field name
      }

      await db.collection(role).doc(phone).set(data);
      log('Registered in collection $role with phone $phone');

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('สมัครสมาชิกสำเร็จ')));

      // Optional: Navigate back to login or home page after successful registration
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e) {
      log('Error during registration: $e'); // Log the specific error
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการสมัคร: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E0FA),
      // --- AppBar ที่เพิ่มเข้ามา ---
      appBar: AppBar(
        title: const Text('สมัครสมาชิก'),
        backgroundColor: const Color(0xFF8C78E8),
        foregroundColor: Colors.white,
        elevation: 0,
        // เพิ่มปุ่ม Back ถ้าต้องการ
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      // --- จบ AppBar ---
      body: SafeArea(
        child: LayoutBuilder(
          // ย้าย LayoutBuilder มาไว้ตรงนี้
          builder: (context, c) {
            final isTall = c.maxHeight > 820;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ===== Avatar + ปุ่มกล้อง =====
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.white,
                              backgroundImage: _pickedImage != null
                                  ? FileImage(File(_pickedImage!.path))
                                  : null,
                              child: _pickedImage == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 60,
                                      color: Colors.black54,
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Material(
                                color: const Color(0xFF8C78E8),
                                shape: const CircleBorder(),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.camera_alt,
                                    color: Color(0xFFE9D5FF),
                                  ),
                                  onPressed: _pickImage,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isTall ? 32 : 20),

                      _RoundedField(
                        controller: phoneCtl,
                        hintText: 'เบอร์โทรศัพท์',
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),

                      _RoundedField(
                        controller: passwordCtl,
                        hintText: 'รหัสผ่าน',
                        obscureText: _obscure,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      const SizedBox(height: 12),

                      _RoundedField(
                        controller: nameCtl,
                        hintText: 'ชื่อ-นามสกุล',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _SegmentButton(
                              label: 'ผู้ใช้',
                              selected: role == 'user',
                              onTap: () => setState(() => role = 'user'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SegmentButton(
                              label: 'ไรเดอร์',
                              selected: role == 'rider',
                              onTap: () => setState(() => role = 'rider'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (role == 'rider') ...[
                        const SizedBox(height: 12),
                        const Text(
                          'ข้อมูลยานพาหนะ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: GestureDetector(
                            onTap: _pickVehicleImage,
                            child: Container(
                              height: 150,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                                image: _vehicleImage != null
                                    ? DecorationImage(
                                        image: FileImage(
                                          File(_vehicleImage!.path),
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _vehicleImage == null
                                  ? const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.directions_car,
                                            size: 40,
                                            color: Colors.black54,
                                          ),
                                          Text('ถ่ายรูปรถ'),
                                        ],
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _RoundedField(
                          controller: vehicleLicensePlateCtl,
                          hintText: 'เลขป้ายทะเบียนรถ',
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (role == 'user')
                        _RoundedField(
                          controller: addressCtl,
                          hintText: _reverseGeocoding
                              ? 'กำลังค้นหาชื่อสถานที่…'
                              : 'ที่อยู่ (พิมพ์แล้วกด ค้นหาตำแหน่ง หรือแตะบนแผนที่)',
                          maxLines: 2,
                        ),

                      if (role == 'user')
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _geocodeAddress,
                              icon: const Icon(Icons.search),
                              label: const Text('ค้นหาตำแหน่ง'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8C78E8),
                                foregroundColor: const Color(0xFFE9D5FF),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _addCurrentAddress,
                              icon: const Icon(Icons.add_location_alt_outlined),
                              label: const Text('เพิ่มที่อยู่นี้'),
                            ),
                            Text('ทั้งหมด ${_addresses.length} ที่อยู่'),
                          ],
                        ),

                      SizedBox(height: isTall ? 16 : 12),

                      if (role == 'user')
                        SizedBox(
                          height: 280,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _center,
                                initialZoom: 12,
                                onTap: (tapPosition, latlng) =>
                                    _reverseGeocode(latlng),
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=66bb35dc3aad4f21b4b0de85b001cb0a', // Consider getting your own API key
                                  userAgentPackageName:
                                      'com.example.deliver_app', // Use your actual package name
                                  maxZoom: 19,
                                ),
                                if (_selectedLatLng != null)
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: _selectedLatLng!,
                                        width: 40,
                                        height: 40,
                                        child: const Icon(
                                          Icons.place,
                                          size: 36,
                                          color: Colors.red, // ทำให้หมุดชัดขึ้น
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),

                      SizedBox(height: isTall ? 20 : 12),

                      SizedBox(
                        height: 57,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8C78E8),
                            foregroundColor: const Color(0xFFE9D5FF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                            elevation: 0,
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFFE9D5FF),
                                    ), // สี loading
                                  ),
                                )
                              : const Text(
                                  'ยืนยัน',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RoundedField extends StatelessWidget {
  const _RoundedField({
    required this.hintText,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.suffix,
    this.maxLines = 1,
    this.textInputAction,
  });

  final String hintText;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final int maxLines;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: obscureText ? 1 : maxLines,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.black.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        suffixIcon: suffix,
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? const Color(0xFF8C78E8) : Colors.white;
    final textColor = selected ? const Color(0xFFE9D5FF) : Colors.black;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        height: 48,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF8C78E8), width: 1),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

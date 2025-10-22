// 🎯 ไฟล์: lib/pages/profile_page.dart (ฉบับแก้ไข เพิ่มการแก้ไขข้อมูล)

import 'dart:io'; // สำหรับ File
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:developer';
import 'package:image_picker/image_picker.dart'; // สำหรับเลือกรูป
import 'package:http/http.dart' as http; // สำหรับอัปโหลดรูป (ถ้าใช้ Cloudinary)
import 'dart:convert'; // สำหรับ jsonDecode

class ProfilePage extends StatefulWidget {
  final String? currentUserPhone;
  final bool isRider;
  const ProfilePage({super.key, this.currentUserPhone, this.isRider = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  var db = FirebaseFirestore.instance;

  // --- ✨ State Variables เพิ่มเติมสำหรับการแก้ไข ---
  bool _isEditing = false; // สถานะกำลังแก้ไข
  bool _isSaving = false; // สถานะกำลังบันทึก
  final _formKey = GlobalKey<FormState>(); // Key สำหรับ Form

  // Controllers สำหรับ TextFields
  late TextEditingController _nameController;
  // เพิ่ม Controllers สำหรับ field อื่นๆ ที่ต้องการแก้ไข (เช่น ทะเบียนรถ)
  late TextEditingController _licensePlateController;

  final ImagePicker _picker = ImagePicker(); // ตัวเลือกรูปภาพ
  XFile? _newProfileImageFile; // ไฟล์รูปโปรไฟล์ใหม่ที่เลือก
  XFile? _newVehicleImageFile; // ไฟล์รูปรถใหม่ที่เลือก (สำหรับ Rider)

  String?
  _dataOriginCollection; // เก็บชื่อ collection ที่ดึงข้อมูลมา ('user' or 'rider')
  // --- จบส่วน State Variables เพิ่มเติม ---

  @override
  void initState() {
    super.initState();
    log('[ProfilePage] Received currentUserPhone: ${widget.currentUserPhone}');
    // Initialize controllers (แต่ยังไม่มีค่า αρχικά)
    _nameController = TextEditingController();
    _licensePlateController = TextEditingController();
    _fetchUserData();
  }

  // ✨ อย่าลืม dispose controllers ✨
  @override
  void dispose() {
    _nameController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    // ... (โค้ด _fetchUserData ที่ค้นหา 2 collections เหมือนเดิม) ...
    final phone = widget.currentUserPhone;
    log('[ProfilePage] Fetching data for phone: $phone');
    if (phone == null || phone.isEmpty) {
      /*...*/
    }

    DocumentSnapshot? doc;
    String? foundInCollection; // เก็บชื่อ collection ที่เจอ
    try {
      log('[ProfilePage] Trying to fetch from collection: user');
      doc = await db.collection('user').doc(phone).get();
      if (doc.exists) foundInCollection = 'user'; // <--- เก็บชื่อ collection

      if (!doc.exists) {
        log('[ProfilePage] Not found in "user". Trying collection: rider');
        doc = await db.collection('rider').doc(phone).get();
        if (doc.exists) foundInCollection = 'rider'; // <--- เก็บชื่อ collection
      }

      if (doc.exists && foundInCollection != null) {
        log('[ProfilePage] User data found in collection: $foundInCollection');
        final fetchedData = doc.data() as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _userData = fetchedData;
            _dataOriginCollection =
                foundInCollection; // <-- บันทึก collection ต้นทาง
            // ✨ ตั้งค่าเริ่มต้นให้ Controllers ✨
            _nameController.text = _userData?['name'] ?? '';
            _licensePlateController.text =
                _userData?['vehicleLicensePlate'] ?? '';
            _isLoading = false;
          });
        }
      } else {
        /* ... ไม่เจอข้อมูล ... */
      }
    } catch (e) {
      /* ... Error handling ... */
    }
    // finally { // ย้าย setState isLoading ไปใน try/catch แล้ว
    //   if (mounted) setState(() => _isLoading = false);
    // }
  }

  // --- ✨ ฟังก์ชันสำหรับการแก้ไข ✨ ---

  // เลือกรูปโปรไฟล์ใหม่
  Future<void> _pickProfileImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null && mounted) {
      setState(() {
        _newProfileImageFile = pickedFile;
      });
    }
  }

  // เลือกรูปรถใหม่ (สำหรับ Rider)
  Future<void> _pickVehicleImage() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile != null && mounted) {
      setState(() {
        _newVehicleImageFile = pickedFile;
      });
    }
  }

  // อัปโหลดรูปภาพ (ตัวอย่าง Cloudinary - ต้องปรับ cloudName, uploadPreset)
  Future<String?> _uploadImage(XFile imageFile, String folderName) async {
    // **สำคัญ:** โค้ดส่วนนี้เป็นเพียงตัวอย่างสำหรับ Cloudinary
    // หากคุณใช้ Firebase Storage วิธีการจะแตกต่างออกไป
    // คุณอาจจะต้องติดตั้ง package `firebase_storage`
    // ดูตัวอย่าง: https://firebase.google.com/docs/storage/flutter/upload-files

    setState(() => _isSaving = true); // แสดง loading ขณะอัปโหลด
    try {
      const cloudName = 'drskwb4o3'; // <-- ใส่ Cloud Name ของคุณ
      const uploadPreset = 'images'; // <-- ใส่ Upload Preset ของคุณ
      final publicId =
          '$folderName/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

      final req = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = folderName
        ..fields['public_id'] = publicId
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        log('[$folderName Image Upload Success]: ${json['secure_url']}');
        return json['secure_url'] as String?;
      } else {
        log(
          '[$folderName Image Upload Failed]: Status ${res.statusCode}, Body: $body',
        );
        throw Exception('Upload failed');
      }
    } catch (e) {
      log('Error uploading $folderName image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('อัปโหลดรูป $folderName ไม่สำเร็จ: $e')),
        );
      }
      return null;
    } finally {
      // ไม่ต้อง setState isSaving ที่นี่ เพราะจะทำตอนจบ _saveChanges
    }
  }

  // บันทึกข้อมูลที่แก้ไข
  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return; // ถ้าข้อมูลใน Form ไม่ถูกต้อง ไม่ต้องทำต่อ
    }
    if (_dataOriginCollection == null || widget.currentUserPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถระบุ collection หรือ ID ผู้ใช้ได้'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    String? newProfilePicUrl;
    String? newVehiclePicUrl;
    Map<String, dynamic> updateData = {};

    try {
      // 1. อัปโหลดรูปโปรไฟล์ใหม่ (ถ้ามีการเลือก)
      if (_newProfileImageFile != null) {
        newProfilePicUrl = await _uploadImage(
          _newProfileImageFile!,
          'profile_pics',
        );
        if (newProfilePicUrl != null) {
          updateData['profilePicURL'] =
              newProfilePicUrl; // ใช้ชื่อ field ที่ถูกต้อง
        } else {
          throw Exception(
            'Failed to upload profile picture.',
          ); // หยุดถ้าอัปโหลดรูปโปรไฟล์ไม่สำเร็จ
        }
      }
      // 2. อัปโหลดรูปรถใหม่ (ถ้ามีการเลือก และเป็น Rider)
      if (widget.isRider && _newVehicleImageFile != null) {
        newVehiclePicUrl = await _uploadImage(
          _newVehicleImageFile!,
          'vehicle_pics',
        );
        if (newVehiclePicUrl != null) {
          updateData['vehiclePicUrl'] =
              newVehiclePicUrl; // ใช้ชื่อ field ที่ถูกต้อง
        } else {
          throw Exception(
            'Failed to upload vehicle picture.',
          ); // หยุดถ้าอัปโหลดรูปรถไม่สำเร็จ
        }
      }

      // 3. รวบรวมข้อมูลที่แก้ไขจาก TextFields (เช็คว่ามีการเปลี่ยนแปลงจริงหรือไม่)
      if (_nameController.text != (_userData?['name'] ?? '')) {
        updateData['name'] = _nameController.text.trim();
      }
      if (widget.isRider &&
          _licensePlateController.text !=
              (_userData?['vehicleLicensePlate'] ?? '')) {
        updateData['vehicleLicensePlate'] = _licensePlateController.text.trim();
      }
      // เพิ่ม field อื่นๆ ที่แก้ไขตามต้องการ

      // 4. ถ้ามีข้อมูลให้อัปเดต ให้เรียก Firestore .update()
      if (updateData.isNotEmpty) {
        log(
          '[ProfilePage] Updating Firestore in $_dataOriginCollection / ${widget.currentUserPhone} with data: $updateData',
        );
        await db
            .collection(_dataOriginCollection!)
            .doc(widget.currentUserPhone!)
            .update(updateData);

        // อัปเดตข้อมูลใน State ทันที (เพื่อให้ UI เปลี่ยน)
        if (mounted) {
          setState(() {
            _userData?.addAll(updateData); // อัปเดตข้อมูลใน _userData
            _newProfileImageFile = null; // เคลียร์รูปที่เลือก
            _newVehicleImageFile = null;
          });
        }
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกข้อมูลเรียบร้อยแล้ว')),
          );
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่มีข้อมูลที่เปลี่ยนแปลง')),
          );
      }

      // 5. ออกจากโหมดแก้ไข
      if (mounted) setState(() => _isEditing = false);
    } catch (e) {
      log('[ProfilePage] Error saving changes: $e');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e')),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ยกเลิกการแก้ไข
  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      // Reset controllers กลับไปเป็นค่าเดิม
      _nameController.text = _userData?['name'] ?? '';
      _licensePlateController.text = _userData?['vehicleLicensePlate'] ?? '';
      _newProfileImageFile = null; // เคลียร์รูปที่เลือก
      _newVehicleImageFile = null;
    });
  }
  // --- จบส่วนฟังก์ชันแก้ไข ---

  void _logout() {
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'แก้ไขโปรไฟล์' : 'โปรไฟล์'),
        automaticallyImplyLeading: false,
        // ✨ เพิ่มปุ่ม Edit/Save/Cancel ใน AppBar ✨
        actions: _isLoading
            ? []
            : [
                // ไม่แสดงปุ่มขณะโหลด
                if (_isEditing)
                  // ปุ่ม Cancel
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSaving
                        ? null
                        : _cancelEdit, // ปิดใช้งานขณะบันทึก
                    tooltip: 'ยกเลิก',
                  ),
                // ปุ่ม Edit หรือ Save
                IconButton(
                  icon: Icon(_isEditing ? Icons.save : Icons.edit),
                  onPressed: _isSaving
                      ? null
                      : (_isEditing
                            ? _saveChanges
                            : () => setState(
                                () => _isEditing = true,
                              )), // ปิดใช้งานขณะบันทึก
                  tooltip: _isEditing ? 'บันทึก' : 'แก้ไข',
                ),
              ],
      ),
      // ✨ แสดง Loading indicator ขณะบันทึก ✨
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isSaving
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text("กำลังบันทึก..."),
                ],
              ),
            )
          : _userData == null
          ? const Center(child: Text('ไม่พบข้อมูลผู้ใช้'))
          : _buildProfileView(), // ใช้ View เดิม แต่ข้างในจะเปลี่ยนตาม _isEditing
    );
  }

  // ✨ แก้ไข _buildProfileView ให้รองรับการแก้ไข ✨
  Widget _buildProfileView() {
    final profileImageUrl = _userData?['profilePicURL'] as String?;
    final addresses = (_userData?['addresses'] as List<dynamic>? ?? []);
    // ดึงข้อมูล Rider มาแสดง (แต่ยังไม่แก้ไขส่วนนี้)
    final vehicleLicensePlate = _userData?['vehicleLicensePlate'] as String?;
    final vehiclePicUrl = _userData?['vehiclePicUrl'] as String?;

    log(
      '[ProfilePage] Addresses data from Firestore: $addresses',
    ); // Log เพื่อยืนยันว่าได้ข้อมูลมา
    log('[ProfilePage] addresses.isEmpty: ${addresses.isEmpty}');

    return Form(
      // ✨ หุ้มด้วย Form ✨
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          // --- รูปโปรไฟล์ (เพิ่มปุ่มแก้ไข) ---
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey.shade300,
                  // ✨ แสดงรูปใหม่ถ้ามีการเลือก หรือรูปเดิม ✨
                  backgroundImage: _newProfileImageFile != null
                      ? FileImage(File(_newProfileImageFile!.path))
                      : (profileImageUrl != null && profileImageUrl.isNotEmpty)
                      ? NetworkImage(profileImageUrl)
                      : null as ImageProvider?, // Cast to ImageProvider?
                  child:
                      (_newProfileImageFile == null &&
                          (profileImageUrl == null || profileImageUrl.isEmpty))
                      ? const Icon(Icons.person, size: 60, color: Colors.white)
                      : null,
                ),
                // ✨ ปุ่มกดแก้ไขรูป (แสดงเมื่อ _isEditing) ✨
                if (_isEditing)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: IconButton(
                        icon: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: _pickProfileImage,
                        tooltip: 'เปลี่ยนรูปโปรไฟล์',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- ชื่อ (แสดง Text หรือ TextFormField) ---
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('ชื่อ'),
              subtitle: _isEditing
                  ? TextFormField(
                      // ✨ ใช้ TextFormField ตอนแก้ไข ✨
                      controller: _nameController,
                      decoration: const InputDecoration(hintText: 'กรอกชื่อ'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'กรุณากรอกชื่อ';
                        }
                        return null;
                      },
                    )
                  : Text(
                      // แสดง Text ปกติ
                      _userData?['name'] ?? 'ไม่มีข้อมูล',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // --- เบอร์โทร (แสดงอย่างเดียว ไม่ให้แก้ไข) ---
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: const Text('เบอร์โทรศัพท์'),
              subtitle: Text(
                widget.currentUserPhone ?? 'ไม่มีข้อมูล',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // --- Role (แสดงอย่างเดียว) ---
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('ประเภทผู้ใช้'),
              subtitle: Text(
                _userData?['role'] ?? 'ไม่มีข้อมูล',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // --- ✨ ส่วนข้อมูล Rider (เพิ่มการแก้ไขถ้าต้องการ) ✨ ---
          if (widget.isRider || _userData?['role'] == 'rider') ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'ข้อมูล Rider',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            // ทะเบียนรถ
            Card(
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('ทะเบียนรถ'),
                subtitle: _isEditing
                    ? TextFormField(
                        // ✨ แก้ไขทะเบียนรถ ✨
                        controller: _licensePlateController,
                        decoration: const InputDecoration(
                          hintText: 'กรอกทะเบียนรถ',
                        ),
                        // validator: ... (เพิ่มถ้าต้องการ)
                      )
                    : Text(
                        // แสดง Text ปกติ
                        vehicleLicensePlate ?? 'ไม่มีข้อมูล',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            // รูปรถ
            Text('รูปยานพาหนะ', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
                image: DecorationImage(
                  // ✨ แสดงรูปรถใหม่ หรือ รูปเดิม ✨
                  image: _newVehicleImageFile != null
                      ? FileImage(File(_newVehicleImageFile!.path))
                      : (vehiclePicUrl != null && vehiclePicUrl.isNotEmpty)
                      ? NetworkImage(vehiclePicUrl)
                      : const AssetImage('assets/images/placeholder.png')
                            as ImageProvider, // ใส่ Placeholder ถ้าไม่มีรูป
                  fit: BoxFit.cover,
                  onError: (exception, stackTrace) {
                    /* แสดง placeholder ถ้าโหลด NetworkImage ไม่ได้ */
                  },
                ),
              ),
              // ✨ ปุ่มกดแก้ไขรูปรถ (แสดงเมื่อ _isEditing) ✨
              child: _isEditing
                  ? Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.camera_alt, size: 16),
                          label: const Text('เปลี่ยนรูป'),
                          onPressed: _pickVehicleImage,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
          ],

          // --- ส่วนที่อยู่ (ตอนนี้แสดงอย่างเดียว) ---
          Text(
            'ที่อยู่ที่บันทึกไว้',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (addresses.isEmpty)
            const Text('ยังไม่มีที่อยู่ที่บันทึกไว้')
          else
            // วนลูปสร้าง Card สำหรับแต่ละที่อยู่
            ...addresses.map((addr) {
              // ตรวจสอบ Type ก่อน Cast เพื่อความปลอดภัย
              if (addr is Map<String, dynamic>) {
                final addressMap = addr; // ไม่ต้อง Cast ซ้ำ
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: Text(
                      addressMap['address'] ?? 'ไม่มีข้อมูลที่อยู่',
                      style: const TextStyle(fontSize: 16),
                    ),
                    // Optional: เพิ่ม onTap เพื่อแก้ไข/ลบ ที่อยู่
                    // onTap: _isEditing ? () { /* ... handle edit/delete ... */ } : null,
                    // trailing: _isEditing ? IconButton(icon: Icon(Icons.delete_outline, color: Colors.red), onPressed: () {/*...*/}) : null,
                  ),
                );
              } else {
                // ถ้าข้อมูลใน Array ไม่ใช่ Map ให้แสดง Widget ว่างๆ หรือ log error
                log(
                  '[ProfilePage] Invalid data type in addresses array: $addr',
                );
                return const SizedBox.shrink(); // แสดง Widget ว่างๆ
              }
            }).toList(),

          // --- ปุ่ม Logout ---
          const SizedBox(height: 48),
          // ✨ ซ่อนปุ่ม Logout ตอนกำลังแก้ไข ✨
          if (!_isEditing)
            ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('ออกจากระบบ'),
              style: ElevatedButton.styleFrom(/* ... */),
            ),
        ],
      ),
    );
  }
}

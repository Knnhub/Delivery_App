// 🎯 ไฟล์: lib/pages/profile_page.dart (ฉบับแก้ไข เพิ่มการแก้ไขข้อมูล + ปรับสี)

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
  late TextEditingController _licensePlateController;

  final ImagePicker _picker = ImagePicker(); // ตัวเลือกรูปภาพ
  XFile? _newProfileImageFile; // ไฟล์รูปโปรไฟล์ใหม่ที่เลือก
  XFile? _newVehicleImageFile; // ไฟล์รูปรถใหม่ที่เลือก (สำหรับ Rider)

  String?
  _dataOriginCollection; // เก็บชื่อ collection ที่ดึงข้อมูลมา ('user' or 'rider')
  // --- จบส่วน State Variables เพิ่มเติม ---

  // --- ✨ สี Theme ---
  final Color _backgroundColor = const Color(0xFFE5E0FA);
  final Color _primaryColor = const Color(0xFF8C78E8);
  final Color _secondaryTextColor = const Color(0xFFE9D5FF);
  // --- จบสี Theme ---

  @override
  void initState() {
    super.initState();
    log('[ProfilePage] Received currentUserPhone: ${widget.currentUserPhone}');
    _nameController = TextEditingController();
    _licensePlateController = TextEditingController();
    _fetchUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _licensePlateController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    final phone = widget.currentUserPhone;
    log('[ProfilePage] Fetching data for phone: $phone');
    if (phone == null || phone.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
        log('[ProfilePage] Error: currentUserPhone is null or empty.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาด: ไม่พบข้อมูลผู้ใช้')),
        );
      }
      return;
    }

    DocumentSnapshot? doc;
    String? foundInCollection;
    setState(() => _isLoading = true);
    try {
      log('[ProfilePage] Trying to fetch from collection: user');
      doc = await db.collection('user').doc(phone).get();
      if (doc.exists) foundInCollection = 'user';

      if (!doc.exists) {
        log('[ProfilePage] Not found in "user". Trying collection: rider');
        doc = await db.collection('rider').doc(phone).get();
        if (doc.exists) foundInCollection = 'rider';
      }

      if (doc != null && doc.exists && foundInCollection != null) {
        log('[ProfilePage] User data found in collection: $foundInCollection');
        final fetchedData = doc.data() as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _userData = fetchedData;
            _dataOriginCollection = foundInCollection;
            _nameController.text = _userData?['name'] ?? '';
            _licensePlateController.text =
                _userData?['vehicleLicensePlate'] ?? '';
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          log('[ProfilePage] User data NOT found for phone: $phone');
          setState(() {
            _isLoading = false;
            _userData = null;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ไม่พบข้อมูลผู้ใช้')));
        }
      }
    } catch (e) {
      log("[ProfilePage] Error fetching user data: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _userData = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการดึงข้อมูล: $e')),
        );
      }
    }
  }

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

  Future<String?> _uploadImage(XFile imageFile, String folderName) async {
    setState(() => _isSaving = true);
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
        throw Exception('Upload failed: ${res.statusCode}');
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
      // Done in _saveChanges
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
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
      if (_newProfileImageFile != null) {
        newProfilePicUrl = await _uploadImage(
          _newProfileImageFile!,
          'profile_pics',
        );
        if (newProfilePicUrl != null) {
          updateData['profilePicUrl'] = newProfilePicUrl;
        } else {
          throw Exception('Failed to upload profile picture.');
        }
      }

      if (widget.isRider && _newVehicleImageFile != null) {
        newVehiclePicUrl = await _uploadImage(
          _newVehicleImageFile!,
          'vehicle_pics',
        );
        if (newVehiclePicUrl != null) {
          updateData['vehiclePicUrl'] = newVehiclePicUrl;
        } else {
          throw Exception('Failed to upload vehicle picture.');
        }
      }

      if (_nameController.text.trim() != (_userData?['name'] ?? '')) {
        updateData['name'] = _nameController.text.trim();
      }
      if (widget.isRider &&
          _licensePlateController.text.trim() !=
              (_userData?['vehicleLicensePlate'] ?? '')) {
        updateData['vehicleLicensePlate'] = _licensePlateController.text.trim();
      }

      if (updateData.isNotEmpty) {
        updateData['updatedAt'] =
            FieldValue.serverTimestamp(); // Add timestamp for update
        log(
          '[ProfilePage] Updating Firestore in $_dataOriginCollection / ${widget.currentUserPhone} with data: $updateData',
        );
        await db
            .collection(_dataOriginCollection!)
            .doc(widget.currentUserPhone!)
            .update(updateData);

        if (mounted) {
          setState(() {
            _userData?.addAll(updateData);
            _newProfileImageFile = null;
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

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _nameController.text = _userData?['name'] ?? '';
      _licensePlateController.text = _userData?['vehicleLicensePlate'] ?? '';
      _newProfileImageFile = null;
      _newVehicleImageFile = null;
    });
  }

  void _logout() {
    // Optional: Add confirmation dialog
    Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
  }

  Widget _buildVehicleImageWidget(String? vehiclePicUrl) {
    if (_newVehicleImageFile != null) {
      return Image.file(
        File(_newVehicleImageFile!.path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildVehiclePlaceholder(error: 'ไฟล์รูปภาพเสียหาย');
        },
      );
    } else if (vehiclePicUrl != null && vehiclePicUrl.isNotEmpty) {
      return Image.network(
        vehiclePicUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          log("Error loading vehicle image: $error");
          return _buildVehiclePlaceholder(error: 'โหลดรูปไม่ได้');
        },
      );
    } else {
      return _buildVehiclePlaceholder();
    }
  }

  Widget _buildVehiclePlaceholder({String? error}) {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              error != null
                  ? Icons.error_outline
                  : Icons.directions_car_outlined,
              size: 40,
              color: error != null ? Colors.red.shade400 : Colors.grey.shade500,
            ),
            const SizedBox(height: 4),
            Text(
              error ?? 'ไม่มีรูปรถ',
              style: TextStyle(
                fontSize: 12,
                color: error != null
                    ? Colors.red.shade700
                    : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --- ✨ ปรับสี Background ---
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'แก้ไขโปรไฟล์' : 'โปรไฟล์',
          style: TextStyle(color: _secondaryTextColor),
        ), // <<< ปรับสี Text
        automaticallyImplyLeading: false,
        // --- ✨ ปรับสี AppBar และ Icon ---
        backgroundColor: _primaryColor,
        foregroundColor: _secondaryTextColor, // <<< ใช้สีนี้สำหรับ Icons ด้วย
        elevation: 0, // <<< เอาเงาออกเพื่อให้เข้า Theme
        actions: _isLoading
            ? []
            : [
                if (_isEditing)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSaving ? null : _cancelEdit,
                    tooltip: 'ยกเลิก',
                  ),
                IconButton(
                  icon: Icon(_isEditing ? Icons.save : Icons.edit),
                  onPressed: _isSaving
                      ? null
                      : (_isEditing
                            ? _saveChanges
                            : () => setState(() => _isEditing = true)),
                  tooltip: _isEditing ? 'บันทึก' : 'แก้ไข',
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isSaving
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                  ), // <<< ปรับสี Loading
                  const SizedBox(height: 10),
                  const Text("กำลังบันทึก..."),
                ],
              ),
            )
          : _userData == null
          ? const Center(child: Text('ไม่พบข้อมูลผู้ใช้'))
          : _buildProfileView(),
    );
  }

  Widget _buildProfileView() {
    final profileImageUrl = _userData?['profilePicUrl'] as String?;
    final addresses = (_userData?['addresses'] as List<dynamic>? ?? []);
    final vehicleLicensePlate = _userData?['vehicleLicensePlate'] as String?;
    final vehiclePicUrl = _userData?['vehiclePicUrl'] as String?;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 60,
                  // --- ✨ ปรับสีพื้นหลัง Avatar ---
                  backgroundColor: Colors.white, // <<< ใช้สีขาวหรือสีเทาอ่อน
                  backgroundImage: _newProfileImageFile != null
                      ? FileImage(File(_newProfileImageFile!.path))
                      : (profileImageUrl != null && profileImageUrl.isNotEmpty)
                      ? NetworkImage(profileImageUrl)
                      : null as ImageProvider?,
                  child:
                      (_newProfileImageFile == null &&
                          (profileImageUrl == null || profileImageUrl.isEmpty))
                      // --- ✨ ปรับสี Icon Placeholder ---
                      ? Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.grey.shade400,
                        ) // <<< สีเทาอ่อนลง
                      : null,
                ),
                if (_isEditing)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 20,
                      // --- ✨ ปรับสีปุ่มกล้อง ---
                      backgroundColor: _primaryColor, // <<< ใช้สีหลัก
                      child: IconButton(
                        icon: const Icon(
                          Icons.camera_alt,
                          // --- ✨ ปรับสีไอคอนกล้อง ---
                          color:
                              Colors.white, // <<< สีขาวหรือ _secondaryTextColor
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

          // --- ใช้ Card หรือ Container ตามชอบ --- (ตัวอย่างใช้ Container + BoxDecoration)
          _buildInfoTile(
            icon: Icons.person_outline,
            title: 'ชื่อ',
            isEditing: _isEditing,
            controller: _nameController,
            initialValue: _userData?['name'] ?? 'ไม่มีข้อมูล',
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'กรุณากรอกชื่อ';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildInfoTile(
            icon: Icons.phone_outlined,
            title: 'เบอร์โทรศัพท์',
            isEditing: false, // เบอร์โทรไม่ให้แก้
            initialValue: widget.currentUserPhone ?? 'ไม่มีข้อมูล',
          ),
          const SizedBox(height: 12),
          _buildInfoTile(
            icon: Icons.verified_user_outlined,
            title: 'ประเภทผู้ใช้',
            isEditing: false, // Role ไม่ให้แก้
            initialValue: _userData?['role'] ?? 'ไม่มีข้อมูล',
          ),

          if (widget.isRider || _userData?['role'] == 'rider') ...[
            const SizedBox(height: 12),
            const Divider(), // <<< อาจปรับสี Divider: color: Colors.grey.shade400
            const SizedBox(height: 12),
            Text(
              'ข้อมูล Rider',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _buildInfoTile(
              icon: Icons.badge_outlined,
              title: 'ทะเบียนรถ',
              isEditing: _isEditing,
              controller: _licensePlateController,
              initialValue: vehicleLicensePlate ?? 'ไม่มีข้อมูล',
              // validator: ... (เพิ่มถ้าต้องการ)
            ),
            const SizedBox(height: 12),
            Text('รูปยานพาหนะ', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white, // <<< พื้นหลังสีขาว
                borderRadius: BorderRadius.circular(12), // <<< เพิ่มขอบมน
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12), // <<< ขอบมนเท่ากัน
                    child: _buildVehicleImageWidget(vehiclePicUrl),
                  ),
                  if (_isEditing)
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.camera_alt, size: 16),
                          label: const Text('เปลี่ยนรูป'),
                          onPressed: _pickVehicleImage,
                          style: ElevatedButton.styleFrom(
                            // --- ✨ ปรับสีปุ่มเปลี่ยนรูป ---
                            backgroundColor: _primaryColor.withOpacity(0.8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ), // <<< ทำให้ปุ่มมนๆ
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Divider(), // <<< อาจปรับสี
            const SizedBox(height: 12),
          ],

          Text(
            'ที่อยู่ที่บันทึกไว้',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (addresses.isEmpty)
            Container(
              // <<< ใส่ Container เพื่อให้มีพื้นหลัง
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'ยังไม่มีที่อยู่ที่บันทึกไว้',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...addresses.map((addr) {
              if (addr is Map<String, dynamic>) {
                final addressMap = addr;
                return Container(
                  // <<< ใช้ Container แทน Card
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.home_outlined,
                      color: _primaryColor,
                    ), // <<< ปรับสี Icon
                    title: Text(
                      addressMap['address'] ?? 'ไม่มีข้อมูลที่อยู่',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                );
              } else {
                log(
                  '[ProfilePage] Invalid data type in addresses array: $addr',
                );
                return const SizedBox.shrink();
              }
            }).toList(),

          const SizedBox(height: 48),
          if (!_isEditing)
            SizedBox(
              // <<< Wrap ด้วย SizedBox เพื่อกำหนดความสูง
              height: 50, // <<< กำหนดความสูง
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text('ออกจากระบบ'),
                style: ElevatedButton.styleFrom(
                  // --- ✨ ปรับสีปุ่ม Logout ให้เข้า Theme ---
                  backgroundColor: Colors.red.shade400, // <<< สีแดงเดิม OK
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    // <<< ทำให้ปุ่มมน
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- ✨ Widget แยกสำหรับแสดงข้อมูลแต่ละรายการ (ปรับปรุง) ✨ ---
  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required bool isEditing,
    required String initialValue,
    TextEditingController? controller,
    String? Function(String?)? validator,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 8,
      ), // <<< เพิ่ม padding แนวตั้งเล็กน้อย
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12), // <<< ขอบมน
      ),
      child: ListTile(
        leading: Icon(icon, color: _primaryColor), // <<< ใช้สีหลัก
        title: Text(
          title,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ), // <<< ทำให้ Title เล็กลงและสีอ่อนลง
        subtitle: isEditing && controller != null
            ? TextFormField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'กรอก$title',
                  border: InputBorder.none, // <<< เอาเส้นใต้ Input ออก
                  isDense: true, // <<< ลดความสูง
                  contentPadding:
                      EdgeInsets.zero, // <<< เอา Padding ของ Input ออก
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ), // <<< Style เหมือน Text ปกติ
                validator: validator,
              )
            : Text(
                initialValue.isEmpty
                    ? 'ไม่มีข้อมูล'
                    : initialValue, // <<< แสดง "ไม่มีข้อมูล" ถ้าค่าว่าง
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

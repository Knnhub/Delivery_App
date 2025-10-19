import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class RiderMapPage extends StatefulWidget {
  final Map<String, dynamic> deliveryData;
  final String deliveryId;

  const RiderMapPage({
    super.key,
    required this.deliveryData,
    required this.deliveryId,
  });

  @override
  State<RiderMapPage> createState() => _RiderMapPageState();
}

class _RiderMapPageState extends State<RiderMapPage> {
  final MapController _mapController = MapController();
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  void _moveToLocation(LatLng location) {
    _mapController.move(location, 15.0);
  }

  Future<String?> _uploadProofImage(XFile imageFile) async {
    try {
      const cloudName = 'drskwb4o3'; // <-- แก้เป็น Cloud Name ของคุณ
      const uploadPreset = 'images';  // <-- แก้เป็น Upload Preset ของคุณ
      const folder = 'proofs';

      final publicId = '${folder}/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

      final req = http.MultipartRequest('POST', url)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = folder
        ..fields['public_id'] = publicId
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final res = await req.send();
      final body = await res.stream.bytesToString();

      if (res.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return json['secure_url'] as String?;
      } else {
        throw Exception('Upload failed with status ${res.statusCode}: $body');
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
      return null;
    }
  }

  Future<void> _updateStatus(String newStatus, {XFile? image}) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      String? imageUrl;
      if (image != null) {
        imageUrl = await _uploadProofImage(image);
        if (imageUrl == null) {
          setState(() => _isSubmitting = false);
          return;
        }
      }

      final Map<String, dynamic> updateData = {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == 'picked') {
        updateData['pickedAt'] = FieldValue.serverTimestamp();
        if(imageUrl != null) updateData['pickupProofImageUrl'] = imageUrl;
      } else if (newStatus == 'delivered') {
        updateData['deliveredAt'] = FieldValue.serverTimestamp();
        if(imageUrl != null) updateData['deliveryProofImageUrl'] = imageUrl;
      } else if (newStatus == 'canceled') {
         updateData['canceledAt'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('deliveries')
          .doc(widget.deliveryId)
          .update(updateData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปเดตสถานะเป็น "$newStatus" เรียบร้อยแล้ว')),
      );
      Navigator.pop(context);

    } catch (e) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickImageAndUpdateStatus(String status) async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1024);
    if (photo != null) {
      await _updateStatus(status, image: photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- ✨ 1. ดึงสถานะปัจจุบันของออเดอร์ ---
    final String currentStatus = widget.deliveryData['status'] as String? ?? 'assigned';

    final senderAddr = widget.deliveryData['senderAddress'] as Map<String, dynamic>? ?? {};
    final receiverAddr = widget.deliveryData['receiverAddress'] as Map<String, dynamic>? ?? {};

    final senderLat = senderAddr['lat'] as double?;
    final senderLng = senderAddr['lng'] as double?;
    final receiverLat = receiverAddr['lat'] as double?;
    final receiverLng = receiverAddr['lng'] as double?;

    final senderLatLng = (senderLat != null && senderLng != null) ? LatLng(senderLat, senderLng) : null;
    final receiverLatLng = (receiverLat != null && receiverLng != null) ? LatLng(receiverLat, receiverLng) : null;

    final markers = <Marker>[
      if (senderLatLng != null) Marker(width: 80.0, height: 80.0, point: senderLatLng, child: const Icon(Icons.store, color: Colors.blue, size: 40)),
      if (receiverLatLng != null) Marker(width: 80.0, height: 80.0, point: receiverLatLng, child: const Icon(Icons.person_pin_circle, color: Colors.red, size: 40)),
    ];
    
    LatLng initialCenter = LatLng(13.736717, 100.523186);
    if (senderLatLng != null) initialCenter = senderLatLng;
    else if (receiverLatLng != null) initialCenter = receiverLatLng;

    return Scaffold(
      appBar: AppBar(title: const Text('แผนที่การจัดส่ง')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: initialCenter, initialZoom: 13.0),
            children: [
              TileLayer(urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", subdomains: const ['a', 'b', 'c']),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.store, color: Colors.blue),
                      title: const Text('จุดรับของ'),
                      subtitle: Text(senderAddr['address'] as String? ?? 'ไม่มีข้อมูล'),
                      trailing: IconButton(
                        icon: const Icon(Icons.center_focus_strong, color: Colors.blue, size: 30),
                        tooltip: 'เลื่อนไปที่จุดรับ',
                        onPressed: senderLatLng != null ? () => _moveToLocation(senderLatLng) : null,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_pin_circle, color: Colors.red),
                      title: const Text('จุดส่งของ'),
                      subtitle: Text(receiverAddr['address'] as String? ?? 'ไม่มีข้อมูล'),
                      trailing: IconButton(
                        icon: const Icon(Icons.center_focus_strong, color: Colors.red, size: 30),
                        tooltip: 'เลื่อนไปที่จุดส่ง',
                        onPressed: receiverLatLng != null ? () => _moveToLocation(receiverLatLng) : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Material(
              elevation: 8,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _isSubmitting
                  ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // --- ✨ 2. ใช้ if-else เพื่อแสดงปุ่มตามสถานะ ---
                        
                        // ถ้าสถานะเป็น 'assigned' ให้แสดงปุ่ม "รับของแล้ว"
                        if (currentStatus == 'assigned')
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('รับของแล้ว'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                              onPressed: () => _pickImageAndUpdateStatus('picked'),
                            ),
                          ),

                        // ถ้าสถานะเป็น 'picked' ให้แสดงปุ่ม "ส่งสำเร็จ"
                        if (currentStatus == 'picked')
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt), // สามารถใช้ไอคอนกล้องเหมือนกันได้
                              label: const Text('ส่งสำเร็จ'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                              onPressed: () => _pickImageAndUpdateStatus('delivered'),
                            ),
                          ),
                          
                        const SizedBox(height: 8),

                        // ปุ่มยกเลิก (แสดงตลอด)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.cancel),
                            label: const Text('ยกเลิกออเดอร์'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('ยืนยันการยกเลิก'),
                                  content: const Text('คุณต้องการยกเลิกออเดอร์นี้ใช่หรือไม่?'),
                                  actions: [
                                    TextButton(child: const Text('ไม่'), onPressed: () => Navigator.pop(context, false)),
                                    TextButton(child: const Text('ใช่, ยกเลิก'), onPressed: () => Navigator.pop(context, true)),
                                  ],
                                ),
                              );
                              if (confirm == true) await _updateStatus('canceled');
                            },
                          ),
                        )
                      ],
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
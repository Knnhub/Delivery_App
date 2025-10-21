import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

import 'dart:async';
import 'package:geolocator/geolocator.dart';

class RiderMapPage extends StatefulWidget {
  final Map<String, dynamic> deliveryData;
  final String deliveryId;
  final String? riderPhone;

  const RiderMapPage({
    super.key,
    required this.deliveryData,
    required this.deliveryId,
    this.riderPhone,
  });

  @override
  State<RiderMapPage> createState() => _RiderMapPageState();
}

class _RiderMapPageState extends State<RiderMapPage> {
  final MapController _mapController = MapController();
  final ImagePicker _picker = ImagePicker();
  bool _isSubmitting = false;

  // ✨ 2. เพิ่ม State Variables สำหรับตำแหน่ง Real-time
  StreamSubscription<Position>? _positionStreamSubscription;
  LatLng? _currentRiderPosition; // ตำแหน่ง Rider ล่าสุด
  StreamSubscription<DocumentSnapshot>?
  _deliveryStreamSubscription; // สำหรับฟัง delivery document

  // เก็บสถานะปัจจุบัน (เพื่อให้ปุ่มเปลี่ยนตาม Realtime)
  late String _currentStatus;

  // LatLng? _riderPositionFromFirestore;

  @override
  void initState() {
    super.initState();
    _currentStatus =
        widget.deliveryData['status'] as String? ??
        'assigned'; // เก็บสถานะเริ่มต้น
    _determinePositionAndStartStream(); // ✨ 3. เริ่มดึงตำแหน่งเมื่อเปิดหน้า
    _listenToDeliveryUpdates(); // ✨ ฟังการอัปเดตสถานะจาก Firestore
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel(); // ✨ 4. ยกเลิก Stream เมื่อปิดหน้า
    _deliveryStreamSubscription?.cancel();
    super.dispose();
  }

  // ✨ 5. ฟังก์ชันขอ Permission และเริ่ม Stream ตำแหน่ง
  Future<void> _determinePositionAndStartStream() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเปิด GPS')));
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('การเข้าถึงตำแหน่งถูกปฏิเสธถาวร')),
      );
      return;
    }

    // Permissions are granted, start listening to position updates.
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, // ความแม่นยำสูง
            distanceFilter: 10, // อัปเดตทุกๆ 10 เมตร
          ),
        ).listen(
          (Position position) {
            print(
              " Position: ${position.latitude}, ${position.longitude}, Accuracy: ${position.accuracy}m",
            );
            print(
              "New Position: ${position.latitude}, ${position.longitude}",
            ); // Log ตำแหน่งใหม่
            if (mounted) {
              final newPosition = LatLng(position.latitude, position.longitude);
              // อัปเดตตำแหน่ง Rider ใน Firestore (เฉพาะเมื่อตำแหน่งเปลี่ยนจริง)
              if (_currentRiderPosition == null ||
                  _currentRiderPosition!.latitude != newPosition.latitude ||
                  _currentRiderPosition!.longitude != newPosition.longitude) {
                _updateRiderLocationInFirestore(newPosition);
              }
              // อัปเดตตำแหน่งใน State เพื่อให้ Marker ขยับทันที (ไม่ต้องรอ Firestore)
              setState(() {
                _currentRiderPosition = newPosition;
              });
            }
          },
          onError: (error) {
            print("Error getting position stream: $error");
          },
        );

    // Get initial position once
    try {
      Position initialPosition = await Geolocator.getCurrentPosition();
      if (mounted) {
        final initialLatLng = LatLng(
          initialPosition.latitude,
          initialPosition.longitude,
        );
        setState(() {
          _currentRiderPosition = initialLatLng;
        });
        _updateRiderLocationInFirestore(initialLatLng); // อัปเดตตำแหน่งเริ่มต้น
        _mapController.move(initialLatLng, 15.0); // ย้ายแผนที่ไปตำแหน่งเริ่มต้น
      }
    } catch (e) {
      print("Error getting initial position: $e");
    }
  }

  // ✨ 6. ฟังก์ชันอัปเดตตำแหน่ง Rider ใน Firestore
  Future<void> _updateRiderLocationInFirestore(LatLng position) async {
    // อัปเดตเฉพาะเมื่อ Rider รับงานแล้ว (assigned หรือ picked)
    final currentStatus = widget.deliveryData['status'] as String? ?? '';
    if (currentStatus == 'assigned' || currentStatus == 'picked') {
      try {
        await FirebaseFirestore.instance
            .collection('deliveries')
            .doc(widget.deliveryId)
            .update({
              'riderLocation': GeoPoint(
                position.latitude,
                position.longitude,
              ), // ใช้ GeoPoint
              // อาจจะอัปเดต timestamp ด้วยก็ได้
            });
      } catch (e) {
        print("Error updating rider location: $e");
        // อาจจะแสดง SnackBar แจ้งเตือน Rider
      }
    }
  }

  // ✨ ฟังก์ชันใหม่สำหรับฟังการเปลี่ยนแปลงสถานะจาก Firestore
  void _listenToDeliveryUpdates() {
    _deliveryStreamSubscription = FirebaseFirestore.instance
        .collection('deliveries')
        .doc(widget.deliveryId)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists && mounted) {
              final data = snapshot.data();
              if (data != null) {
                // อัปเดตสถานะใน widget.deliveryData เพื่อให้ปุ่มเปลี่ยนตาม
                setState(() {
                  widget.deliveryData['status'] = data['status'];
                });
                // ถ้าสถานะเป็น delivered หรือ canceled ให้ออกจากหน้านี้
                if (data['status'] == 'delivered' ||
                    data['status'] == 'canceled') {
                  // หน่วงเวลาก่อน pop เล็กน้อยเพื่อให้ Rider เห็นสถานะล่าสุด
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) {
                      Navigator.pop(context);
                    }
                  });
                }
              }
            }
          },
          onError: (error) {
            print("Error listening to delivery updates: $error");
          },
        );
  }

  // ✨ ฟังก์ชันเลื่อนแผนที่ไปตำแหน่งที่กำหนด
  void _moveToLocation(LatLng location) {
    _mapController.move(location, 15.0);
  }

  Future<String?> _uploadProofImage(XFile imageFile) async {
    try {
      const cloudName = 'drskwb4o3'; // <-- แก้เป็น Cloud Name ของคุณ
      const uploadPreset = 'images'; // <-- แก้เป็น Upload Preset ของคุณ
      const folder = 'proofs';

      final publicId =
          '${folder}/${DateTime.now().millisecondsSinceEpoch}_${imageFile.name}';
      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
      );

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
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
        if (imageUrl != null) updateData['pickupProofImageUrl'] = imageUrl;
      } else if (newStatus == 'delivered') {
        updateData['deliveredAt'] = FieldValue.serverTimestamp();
        if (imageUrl != null) updateData['deliveryProofImageUrl'] = imageUrl;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickImageAndUpdateStatus(String status) async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (photo != null) {
      await _updateStatus(status, image: photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- ✨ 1. ดึงสถานะปัจจุบันของออเดอร์ ---

    final String currentStatus =
        widget.deliveryData['status'] as String? ?? 'assigned';

    final senderAddr =
        widget.deliveryData['senderAddress'] as Map<String, dynamic>? ?? {};
    final receiverAddr =
        widget.deliveryData['receiverAddress'] as Map<String, dynamic>? ?? {};

    final senderLat = senderAddr['lat'] as double?;
    final senderLng = senderAddr['lng'] as double?;
    final receiverLat = receiverAddr['lat'] as double?;
    final receiverLng = receiverAddr['lng'] as double?;

    final senderLatLng = (senderLat != null && senderLng != null)
        ? LatLng(senderLat, senderLng)
        : null;
    final receiverLatLng = (receiverLat != null && receiverLng != null)
        ? LatLng(receiverLat, receiverLng)
        : null;

    // log(
    //   'Rider Position from Firestore for Marker: $_riderPositionFromFirestore',
    // );
    final markers = <Marker>[
      if (senderLatLng != null)
        Marker(
          width: 80.0,
          height: 80.0,
          point: senderLatLng,
          child: const Icon(Icons.store, color: Colors.blue, size: 40),
        ),
      if (receiverLatLng != null)
        Marker(
          width: 80.0,
          height: 80.0,
          point: receiverLatLng,
          child: const Icon(
            Icons.person_pin_circle,
            color: Colors.red,
            size: 40,
          ),
        ),
      // ✨ Marker ตำแหน่ง Rider (ไอคอนมอเตอร์ไซค์)
      if (_currentRiderPosition != null)
        Marker(
          width: 40.0, // ปรับขนาดตามต้องการ
          height: 40.0,
          point: _currentRiderPosition!,
          child: Transform.rotate(
            // Optional: หมุนไอคอนตามทิศทาง (ต้องใช้ข้อมูล heading จาก geolocator เพิ่มเติม)
            angle: 0, // ใส่ค่าองศาที่ได้จาก position.heading (ถ้ามี)
            //
            child: const Icon(Icons.motorcycle, color: Colors.purple, size: 30),
          ),
        ),
    ];

    LatLng initialCenter = LatLng(16.1832, 103.3035);
    if (_currentRiderPosition != null) {
      initialCenter = _currentRiderPosition!;
    } else if (senderLatLng != null) {
      initialCenter = senderLatLng;
    } else if (receiverLatLng != null) {
      initialCenter = receiverLatLng;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('แผนที่การจัดส่ง')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",

                // subdomains: const ['a', 'b', 'c'],
              ),
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
                      subtitle: Text(
                        senderAddr['address'] as String? ?? 'ไม่มีข้อมูล',
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.center_focus_strong,
                          color: Colors.blue,
                          size: 30,
                        ),
                        tooltip: 'เลื่อนไปที่จุดรับ',
                        onPressed: senderLatLng != null
                            ? () => _moveToLocation(senderLatLng)
                            : null,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.person_pin_circle,
                        color: Colors.red,
                      ),
                      title: const Text('จุดส่งของ'),
                      subtitle: Text(
                        receiverAddr['address'] as String? ?? 'ไม่มีข้อมูล',
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.center_focus_strong,
                          color: Colors.red,
                          size: 30,
                        ),
                        tooltip: 'เลื่อนไปที่จุดส่ง',
                        onPressed: receiverLatLng != null
                            ? () => _moveToLocation(receiverLatLng)
                            : null,
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
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _isSubmitting
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
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
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: () =>
                                    _pickImageAndUpdateStatus('picked'),
                              ),
                            ),

                          // ถ้าสถานะเป็น 'picked' ให้แสดงปุ่ม "ส่งสำเร็จ"
                          if (currentStatus == 'picked')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.camera_alt,
                                ), // สามารถใช้ไอคอนกล้องเหมือนกันได้
                                label: const Text('ส่งสำเร็จ'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                                onPressed: () =>
                                    _pickImageAndUpdateStatus('delivered'),
                              ),
                            ),

                          const SizedBox(height: 8),

                          // ปุ่มยกเลิก (แสดงตลอด)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.cancel),
                              label: const Text('ยกเลิกออเดอร์'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('ยืนยันการยกเลิก'),
                                    content: const Text(
                                      'คุณต้องการยกเลิกออเดอร์นี้ใช่หรือไม่?',
                                    ),
                                    actions: [
                                      TextButton(
                                        child: const Text('ไม่'),
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                      ),
                                      TextButton(
                                        child: const Text('ใช่, ยกเลิก'),
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true)
                                  await _updateStatus('created');
                              },
                            ),
                          ),
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

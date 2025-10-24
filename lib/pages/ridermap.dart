// lib/pages/ridermap.dart
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

// --- ✨ สี Theme ที่จะใช้ (สีม่วง) ---
const Color primaryColor = Color(0xFF8C78E8);
const Color backgroundColor = Color(0xFFE5E0FA);
const Color secondaryTextColor = Color(0xFFE9D5FF);
// --- จบสี Theme ---

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

  // ✨ State Variables สำหรับตำแหน่ง Real-time
  StreamSubscription<Position>? _positionStreamSubscription;
  LatLng? _currentRiderPosition; // ตำแหน่ง Rider ล่าสุด
  StreamSubscription<DocumentSnapshot>?
  _deliveryStreamSubscription; // สำหรับฟัง delivery document

  // เก็บสถานะปัจจุบัน (เพื่อให้ปุ่มเปลี่ยนตาม Realtime)
  late String _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus =
        widget.deliveryData['status'] as String? ??
        'assigned'; // เก็บสถานะเริ่มต้น
    _determinePositionAndStartStream(); // ✨ เริ่มดึงตำแหน่งเมื่อเปิดหน้า
    _listenToDeliveryUpdates(); // ✨ ฟังการอัปเดตสถานะจาก Firestore
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel(); // ✨ ยกเลิก Stream เมื่อปิดหน้า
    _deliveryStreamSubscription?.cancel();
    super.dispose();
  }

  // ✨ ฟังก์ชันขอ Permission และเริ่ม Stream ตำแหน่ง
  Future<void> _determinePositionAndStartStream() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return; // Check mounted before showing SnackBar
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเปิด GPS')));
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
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
            distanceFilter: 10, // ✅ อัปเดตทุกๆ 10 เมตร
          ),
        ).listen(
          (Position position) {
            log(
              " Position: ${position.latitude}, ${position.longitude}, Accuracy: ${position.accuracy}m",
            );
            log(
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
            log("Error getting position stream: $error");
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
      log("Error getting initial position: $e");
    }
  }

  // ✨ ฟังก์ชันอัปเดตตำแหน่ง Rider ใน Firestore
  Future<void> _updateRiderLocationInFirestore(LatLng position) async {
    // อัปเดตเฉพาะเมื่อ Rider รับงานแล้ว (assigned หรือ picked)
    // ใช้ _currentStatus ที่อัปเดตจาก Firestore listener
    if (_currentStatus == 'assigned' || _currentStatus == 'picked') {
      try {
        await FirebaseFirestore.instance
            .collection('deliveries')
            .doc(widget.deliveryId)
            .update({
              'riderLocation': GeoPoint(
                position.latitude,
                position.longitude,
              ), // ใช้ GeoPoint
              'riderLocationTimestamp':
                  FieldValue.serverTimestamp(), // อัปเดต timestamp ด้วย
            });
        log('Firestore location updated for ${widget.deliveryId}');
      } catch (e) {
        log("Error updating rider location: $e");
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
                final newStatus = data['status'] as String? ?? 'unknown';
                log('[RiderMap] Firestore status update: $newStatus');
                // อัปเดตสถานะใน State เพื่อให้ปุ่มเปลี่ยนตาม
                setState(() {
                  _currentStatus = newStatus;
                  // อัปเดต widget.deliveryData ด้วย (เผื่อมีการใช้ที่อื่นใน build)
                  widget.deliveryData['status'] = newStatus;
                });
                // ถ้าสถานะเป็น delivered หรือ canceled ให้ออกจากหน้านี้
                if (newStatus == 'delivered' || newStatus == 'canceled') {
                  log(
                    '[RiderMap] Status changed to $newStatus, closing page soon...',
                  );
                  // หน่วงเวลาก่อน pop เล็กน้อยเพื่อให้ Rider เห็นสถานะล่าสุด
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) {
                      Navigator.pop(context);
                    }
                  });
                }
              }
            } else if (mounted) {
              // Handle case where document is deleted
              log('[RiderMap] Delivery document ${widget.deliveryId} deleted.');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ข้อมูลการจัดส่งถูกลบ')),
              );
              Navigator.pop(context);
            }
          },
          onError: (error) {
            log("Error listening to delivery updates: $error");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('เกิดข้อผิดพลาดในการฟังข้อมูล: $error')),
              );
            }
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
        log('Image Upload Success: ${json['secure_url']}');
        return json['secure_url'] as String?;
      } else {
        log('Image Upload Failed: Status ${res.statusCode}, Body: $body');
        throw Exception('Upload failed with status ${res.statusCode}: $body');
      }
    } catch (e) {
      log('Error uploading proof image: $e');
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')));
      return null;
    }
  }

  Future<void> _updateStatus(
    String newStatus, {
    XFile? image,
    String? riderIdToClear,
  }) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    log(
      '[RiderMap] Updating status to: $newStatus (riderIdToClear: $riderIdToClear)',
    );

    try {
      String? imageUrl;
      if (image != null) {
        imageUrl = await _uploadProofImage(image);
        if (imageUrl == null) {
          log('[RiderMap] Image upload failed, aborting status update.');
          if (mounted) {
            // Check mount before setting state
            setState(() => _isSubmitting = false);
          }
          return; // Stop if image upload failed
        }
      }

      final Map<String, dynamic> updateData = {
        'status': newStatus, // Set the target status initially
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == 'picked') {
        updateData['pickedAt'] = FieldValue.serverTimestamp();
        if (imageUrl != null) updateData['pickupProofImageUrl'] = imageUrl;
      } else if (newStatus == 'delivered') {
        updateData['deliveredAt'] = FieldValue.serverTimestamp();
        if (imageUrl != null) updateData['deliveryProofImageUrl'] = imageUrl;
      } else if (newStatus == 'created' && riderIdToClear != null) {
        // Condition for cancellation by rider
        log('[RiderMap] Processing cancellation by rider.');
        updateData['status'] =
            'created'; // Ensure status is set back to created
        updateData['canceledAt'] =
            FieldValue.serverTimestamp(); // Record cancellation time
        updateData['riderId'] = null; // Clear riderId
        updateData['assignedAt'] = null; // Clear assignment time
        updateData['riderLocation'] = null; // Clear rider location data
        updateData['riderLocationTimestamp'] = null;
        updateData['riderLocationAccuracy'] = null;
        // Keep existing fields like pickedAt, pickupProofImageUrl etc. if they exist
      } else if (newStatus == 'canceled') {
        // General cancellation (maybe by admin or system)
        updateData['canceledAt'] = FieldValue.serverTimestamp();
        // Optionally clear rider info if needed based on rules
        // updateData['riderId'] = null;
        // updateData['assignedAt'] = null;
      }

      log('[RiderMap] Data to update in Firestore: $updateData');
      await FirebaseFirestore.instance
          .collection('deliveries')
          .doc(widget.deliveryId)
          .update(updateData);
      log('[RiderMap] Firestore update successful.');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปเดตสถานะเป็น "$newStatus" เรียบร้อยแล้ว')),
      );

      // Only pop if the update wasn't a cancellation back to 'created'
      // If it was cancelled back to 'created', stay on the map briefly? Or pop immediately? Let's pop.
      Navigator.pop(context);
    } catch (e) {
      log('[RiderMap] Error updating status: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการอัปเดตสถานะ: $e')),
      );
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
    // --- 1. ดึงสถานะปัจจุบันของออเดอร์ (ใช้ State variable _currentStatus) ---
    final String currentStatus = _currentStatus; // Use state variable

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

    // --- ✨ คำนวณระยะทาง ---
    final Distance distance = const Distance();
    double distanceToSender = double.infinity;
    double distanceToReceiver = double.infinity;

    if (_currentRiderPosition != null) {
      if (senderLatLng != null) {
        distanceToSender = distance(
          _currentRiderPosition!,
          senderLatLng,
        ); // distance in meters
      }
      if (receiverLatLng != null) {
        distanceToReceiver = distance(
          _currentRiderPosition!,
          receiverLatLng,
        ); // distance in meters
      }
    }
    log('[RiderMap Build] Distance to Sender: $distanceToSender m');
    log('[RiderMap Build] Distance to Receiver: $distanceToReceiver m');
    log('[RiderMap Build] Current Rider Position: $_currentRiderPosition');

    // --- ✨ เงื่อนไขการกดปุ่ม ---
    // กด "รับของแล้ว" ได้เมื่อ status='assigned' และอยู่ใกล้จุดรับ <= 20 เมตร
    final bool canPickup =
        currentStatus == 'assigned' && distanceToSender <= 20.0;
    // กด "ส่งสำเร็จ" ได้เมื่อ status='picked' และอยู่ใกล้จุดส่ง <= 20 เมตร
    final bool canDeliver =
        currentStatus == 'picked' && distanceToReceiver <= 20.0;

    log(
      '[RiderMap Build] Status: $currentStatus, Can Pickup: $canPickup, Can Deliver: $canDeliver',
    );

    // --- Markers ---
    final markers = <Marker>[
      if (senderLatLng != null)
        Marker(
          width: 80.0,
          height: 80.0,
          point: senderLatLng,
          child: Tooltip(
            message: 'จุดรับ: ${senderAddr['address'] ?? ''}',
            child: const Icon(Icons.store, color: Colors.blue, size: 40),
          ),
        ),
      if (receiverLatLng != null)
        Marker(
          width: 80.0,
          height: 80.0,
          point: receiverLatLng,
          child: Tooltip(
            message: 'จุดส่ง: ${receiverAddr['address'] ?? ''}',
            child: const Icon(
              Icons.person_pin_circle,
              color: Colors.red,
              size: 40,
            ),
          ),
        ),
      // ✨ Marker ตำแหน่ง Rider (ไอคอนมอเตอร์ไซค์)
      if (_currentRiderPosition != null)
        Marker(
          width: 40.0, // ปรับขนาดตามต้องการ
          height: 40.0,
          point: _currentRiderPosition!,
          child: Tooltip(
            message: 'ตำแหน่งของคุณ',
            // --- ✨ ปรับสี Icon Rider ---
            child: Icon(
              Icons.motorcycle,
              color: primaryColor,
              size: 30,
            ), // <<< สีม่วง
          ),
        ),
    ];

    LatLng initialCenter = LatLng(16.1832, 103.3035); // Default Mahasarakham
    if (_currentRiderPosition != null) {
      initialCenter = _currentRiderPosition!;
    } else if (senderLatLng != null) {
      initialCenter = senderLatLng;
    } else if (receiverLatLng != null) {
      initialCenter = receiverLatLng;
    }

    return Scaffold(
      // --- ✨ ปรับสี AppBar ---
      appBar: AppBar(
        title: const Text('แผนที่การจัดส่ง'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // --- ✨ ปรับสีพื้นหลัง Scaffold ---
      backgroundColor: backgroundColor,
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
                    "https://tile.openstreetmap.org/{z}/{x}/{y}.png", // Corrected URL
                // subdomains: const ['a', 'b', 'c'], // Not needed for OSM default
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
                  // --- ✨ ปรับ Card ที่อยู่ ---
                  Card(
                    color: Colors.white,
                    surfaceTintColor: Colors.white,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.store, color: Colors.blue),
                      title: const Text('จุดรับของ'),
                      subtitle: Text(
                        senderAddr['address'] as String? ?? 'ไม่มีข้อมูล',
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.navigation_outlined, // Changed Icon
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
                    color: Colors.white,
                    surfaceTintColor: Colors.white,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                          Icons.navigation_outlined, // Changed Icon
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
              // --- ✨ ปรับสี Bottom Sheet ---
              color: Colors.white, // <<< สีขาว
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _isSubmitting
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  primaryColor,
                                ),
                              ), // <<< ปรับสี
                              SizedBox(height: 8),
                              Text("กำลังดำเนินการ..."),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // --- ✨ ปุ่ม "รับของแล้ว" ---
                          if (currentStatus == 'assigned')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('รับของแล้ว'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      canPickup // ✨ ใช้เงื่อนไขสี
                                      // --- ✨ ปรับสีปุ่ม ---
                                      ? primaryColor // <<< สีม่วง
                                      : Colors.grey, // สีเทาถ้ากดไม่ได้
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  // --- ✨ ปรับ Shape ปุ่ม ---
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                onPressed: canPickup
                                    ? () => _pickImageAndUpdateStatus('picked')
                                    : null, // null = disabled
                              ),
                            ),

                          // --- ✨ ปุ่ม "ส่งสำเร็จ" ---
                          if (currentStatus == 'picked')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('ส่งสำเร็จ'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      canDeliver // ✨ ใช้เงื่อนไขสี
                                      // --- ✨ ปรับสีปุ่ม ---
                                      ? primaryColor // <<< สีม่วง
                                      : Colors.grey, // สีเทาถ้ากดไม่ได้
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  // --- ✨ ปรับ Shape ปุ่ม ---
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                onPressed: canDeliver
                                    ? () =>
                                          _pickImageAndUpdateStatus('delivered')
                                    : null, // null = disabled
                              ),
                            ),

                          // --- ข้อความแจ้งเตือน (Optional) ---
                          if (currentStatus == 'assigned' && !canPickup)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                distanceToSender == double.infinity
                                    ? 'กำลังรอตำแหน่ง...'
                                    : 'กรุณาเข้าใกล้จุดรับของ (ระยะทาง: ${distanceToSender.toStringAsFixed(1)} เมตร)',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (currentStatus == 'picked' && !canDeliver)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                distanceToReceiver == double.infinity
                                    ? 'กำลังรอตำแหน่ง...'
                                    : 'กรุณาเข้าใกล้จุดส่งของ (ระยะทาง: ${distanceToReceiver.toStringAsFixed(1)} เมตร)',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),

                          const SizedBox(height: 8),

                          // --- ปุ่มยกเลิก ---
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.cancel),
                              label: const Text('ยกเลิกออเดอร์'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                // --- ✨ ปรับ Shape ปุ่ม ---
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ), // <<< ปรับ Padding ให้ใกล้เคียง
                              ),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('ยืนยันการยกเลิก'),
                                    content: const Text(
                                      'คุณต้องการยกเลิกออเดอร์นี้ และคืนงานสู่รายการใหม่ใช่หรือไม่?',
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
                                if (confirm == true) {
                                  await _updateStatus(
                                    'created',
                                    riderIdToClear: widget.riderPhone,
                                  );
                                }
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
} // End _RiderMapPageState

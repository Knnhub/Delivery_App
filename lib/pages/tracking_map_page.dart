// 🎯 ไฟล์ใหม่: lib/pages/tracking_map_page.dart

import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
// import 'package:geolocator/geolocator.dart'; // Optional: ถ้าต้องการแสดงตำแหน่ง User ด้วย

class TrackingMapPage extends StatefulWidget {
  final String deliveryId;

  const TrackingMapPage({super.key, required this.receiverPhone});

  @override
  State<TrackingMapPage> createState() => _TrackingMapPageState();
}

class _TrackingMapPageState extends State<TrackingMapPage> {
  final MapController _mapController = MapController();
  StreamSubscription? _deliveriesSubscription;
  Map<String, LatLng> _riderLocations =
      {}; // เก็บตำแหน่ง Rider แต่ละคน (Key: deliveryId, Value: LatLng)
  LatLng? _userHomeLocation; // Optional: ตำแหน่งบ้านผู้ใช้

  // ตำแหน่งเริ่มต้น (อาจจะปรับตามตำแหน่งผู้ใช้หรือ Rider คนแรก)
  final LatLng _initialCenter = const LatLng(16.1832, 103.3035); // มหาสารคาม
  final double _initialZoom = 13.0;

  @override
  void initState() {
    super.initState();
    _startListeningToDeliveries();
    // Optional: ดึงตำแหน่งบ้านของผู้ใช้จาก profile มาแสดงเป็น Marker
    // _fetchUserHomeLocation();
  }

  @override
  void dispose() {
    _deliveriesSubscription?.cancel();
    super.dispose();
  }

  // Optional: ดึงตำแหน่งบ้านผู้ใช้
  // Future<void> _fetchUserHomeLocation() async {
  //   try {
  //     final userDoc = await FirebaseFirestore.instance.collection('user').doc(widget.receiverPhone).get();
  //     if (userDoc.exists) {
  //       final data = userDoc.data();
  //       final addresses = data?['addresses'] as List<dynamic>?;
  //       if (addresses != null && addresses.isNotEmpty) {
  //         // สมมติว่าใช้ที่อยู่แรกเป็นบ้าน
  //         final homeAddr = addresses.first as Map<String, dynamic>?;
  //         final lat = (homeAddr?['lat'] as num?)?.toDouble();
  //         final lng = (homeAddr?['lng'] as num?)?.toDouble();
  //         if (lat != null && lng != null && mounted) {
  //           setState(() => _userHomeLocation = LatLng(lat, lng));
  //           // อาจจะย้าย map มาตำแหน่งบ้าน
  //           // _mapController.move(_userHomeLocation!, _initialZoom);
  //         }
  //       }
  //     }
  //   } catch (e) {
  //     log("Error fetching user home location: $e");
  //   }
  // }

  // ฟังก์ชันเริ่มฟัง Deliveries ที่กำลังมาส่ง
  void _startListeningToDeliveries() {
    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('receiverPhone', isEqualTo: widget.receiverPhone)
        .where(
          'status',
          whereIn: ['assigned', 'picked'],
        ); // กรองเฉพาะที่กำลังเดินทาง

    _deliveriesSubscription?.cancel(); // ยกเลิก Listener เก่า
    _deliveriesSubscription = query.snapshots().listen(
      (snapshot) {
        log(
          "[TrackingMap] Received ${snapshot.docs.length} active deliveries.",
        );
        Map<String, LatLng> updatedLocations = {};
        bool shouldMoveMap =
            _riderLocations.isEmpty; // ย้ายแผนที่ถ้ายังไม่เคยมี Rider แสดง

        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final riderLocationGeoPoint = data['riderLocation'] as GeoPoint?;

          if (riderLocationGeoPoint != null) {
            final riderLatLng = LatLng(
              riderLocationGeoPoint.latitude,
              riderLocationGeoPoint.longitude,
            );
            updatedLocations[doc.id] = riderLatLng; // ใช้ deliveryId เป็น Key
            log("[TrackingMap] Rider for ${doc.id} at: $riderLatLng");
          } else {
            log("[TrackingMap] Rider location not found for ${doc.id}");
          }
        }

        if (mounted) {
          setState(() {
            _riderLocations = updatedLocations;
          });

          // ย้ายแผนที่ไปหา Rider คนแรกที่เจอ (ถ้ายังไม่เคยแสดง Rider มาก่อน)
          if (shouldMoveMap && updatedLocations.isNotEmpty) {
            final firstRiderLocation = updatedLocations.values.first;
            _mapController.move(firstRiderLocation, 15.0); // ซูมเข้าไปใกล้ขึ้น
          }
        }
      },
      onError: (error) {
        log("[TrackingMap] Error listening to deliveries: $error");
        if (mounted) {
          setState(() => _riderLocations = {}); // เคลียร์ตำแหน่งถ้า error
        }
      },
    );
    log(
      "[TrackingMap] Started listening for deliveries to ${widget.receiverPhone}",
    );
  }

  @override
  Widget build(BuildContext context) {
    // สร้าง Markers
    final markers = <Marker>[
      // Marker สำหรับ Rider แต่ละคน
      ..._riderLocations.entries.map((entry) {
        final deliveryId = entry.key;
        final position = entry.value;
        return Marker(
          width: 40.0,
          height: 40.0,
          point: position,
          child: Tooltip(
            message:
                'Rider ส่งงาน $deliveryId', // อาจจะแสดงชื่อ Rider หรือข้อมูลอื่น ๆ
            child: Image.asset(
              'assets/images/motorcycle_icon.png',
            ), // ใช้ไอคอนมอเตอร์ไซค์
          ),
        );
      }),

      // Optional: Marker ตำแหน่งบ้านของผู้ใช้
      if (_userHomeLocation != null)
        Marker(
          width: 80.0,
          height: 80.0,
          point: _userHomeLocation!,
          child: Tooltip(
            message: "ตำแหน่งของคุณ",
            child: const Icon(Icons.home, color: Colors.green, size: 40),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('ติดตามตำแหน่ง Rider')),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter:
              _userHomeLocation ?? _initialCenter, // เริ่มที่บ้าน ถ้ามี
          initialZoom: _initialZoom,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
          ),
          MarkerLayer(markers: markers),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // ปุ่มกลับมาตำแหน่งเริ่มต้น / บ้าน
        onPressed: () {
          _mapController.move(
            _userHomeLocation ?? _initialCenter,
            _initialZoom,
          );
        },
        tooltip: 'กลับไปตำแหน่งเริ่มต้น',
        child: const Icon(Icons.my_location), // หรือ Icons.home
      ),
    );
  }
}

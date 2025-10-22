// 🎯 ไฟล์: lib/pages/tracking_map_page.dart (Multi-Rider Tracking)

import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class TrackingMapPage extends StatefulWidget {
  final String receiverPhone; // ✅ รับเบอร์ผู้รับแทน deliveryId

  const TrackingMapPage({super.key, required this.receiverPhone});

  @override
  State<TrackingMapPage> createState() => _TrackingMapPageState();
}

class _TrackingMapPageState extends State<TrackingMapPage> {
  final MapController _mapController = MapController();
  StreamSubscription<QuerySnapshot>? _deliveriesSub;

  Map<String, LatLng> _riderLocations =
      {}; // เก็บตำแหน่ง Rider หลายคน (key = deliveryId)
  LatLng? _receiverLocation; // ตำแหน่งผู้รับ
  bool _hasMovedOnce = false;

  // ศูนย์เริ่มต้น (มหาสารคาม)
  final LatLng _initialCenter = const LatLng(16.1832, 103.3035);
  final double _initialZoom = 13.0;

  @override
  void initState() {
    super.initState();
    _listenDeliveriesToReceiver();
  }

  @override
  void dispose() {
    _deliveriesSub?.cancel();
    super.dispose();
  }

  void _listenDeliveriesToReceiver() {
    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('receiverPhone', isEqualTo: widget.receiverPhone)
        .where('status', whereIn: ['assigned', 'picked']); // งานที่กำลังเดินทาง

    _deliveriesSub = query.snapshots().listen(
      (snapshot) {
        log('[TrackingMap] Found ${snapshot.docs.length} deliveries.');

        final newRiderLocations = <String, LatLng>{};
        LatLng? receiverLatLng;

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;

          // 📍 ดึงตำแหน่ง Rider
          final riderLoc = data['riderLocation'] as GeoPoint?;
          if (riderLoc != null) {
            newRiderLocations[doc.id] = LatLng(
              riderLoc.latitude,
              riderLoc.longitude,
            );
          }

          // 🏠 ดึงตำแหน่งผู้รับ (ใช้ของงานแรก)
          if (receiverLatLng == null && data['receiverAddress'] != null) {
            final recv = data['receiverAddress'] as Map<String, dynamic>;
            final lat = (recv['lat'] as num?)?.toDouble();
            final lng = (recv['lng'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              receiverLatLng = LatLng(lat, lng);
            }
          }
        }

        if (mounted) {
          setState(() {
            _riderLocations = newRiderLocations;
            _receiverLocation = receiverLatLng;
          });

          // ซูมกล้องครั้งแรกเมื่อมีข้อมูล
          if (!_hasMovedOnce && newRiderLocations.isNotEmpty) {
            _mapController.move(newRiderLocations.values.first, 14.5);
            _hasMovedOnce = true;
          }
        }
      },
      onError: (e) {
        log('[TrackingMap] error: $e');
      },
    );

    log(
      '[TrackingMap] Listening deliveries for receiver: ${widget.receiverPhone}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      // 🛵 Marker สำหรับ Rider แต่ละคน
      ..._riderLocations.entries.map((entry) {
        return Marker(
          width: 40,
          height: 40,
          point: entry.value,
          child: Tooltip(
            message: 'Rider จากงาน ${entry.key.substring(0, 6)}',
            child: Image.asset(
              'assets/images/motorcycle_icon.png',
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.two_wheeler, size: 30, color: Colors.blue),
            ),
          ),
        );
      }),

      // 🏠 Marker ผู้รับพัสดุ
      if (_receiverLocation != null)
        Marker(
          width: 80,
          height: 80,
          point: _receiverLocation!,
          child: const Tooltip(
            message: "ที่อยู่ของคุณ",
            child: Icon(Icons.home, color: Colors.green, size: 40),
          ),
        ),
    ];

    // ✅ เส้นเชื่อมแต่ละ Rider → ผู้รับ (optional)
    final polylines = <Polyline>[
      if (_receiverLocation != null)
        ..._riderLocations.values.map(
          (pos) => Polyline(
            points: [pos, _receiverLocation!],
            strokeWidth: 4,
            color: Colors.orangeAccent,
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('ติดตาม Rider ที่กำลังมาหาคุณ')),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _receiverLocation ?? _initialCenter,
          initialZoom: _initialZoom,
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=YOUR_THUNDERFOREST_API_KEY',
            userAgentPackageName: 'com.yourcompany.deliveryapp',
          ),
          RichAttributionWidget(
            attributions: const [
              TextSourceAttribution(
                'Maps © Thunderforest, Data © OpenStreetMap contributors',
              ),
            ],
            showFlutterMapAttribution: false,
          ),
          PolylineLayer(polylines: polylines),
          MarkerLayer(markers: markers),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_riderLocations.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: 'fitAll',
              onPressed: _fitAllMarkers,
              label: const Text('แสดงทุก Rider'),
              icon: const Icon(Icons.group),
            ),
          const SizedBox(height: 8),
          if (_receiverLocation != null)
            FloatingActionButton.extended(
              heroTag: 'toReceiver',
              onPressed: () => _mapController.move(_receiverLocation!, 15.0),
              label: const Text('ไปยังบ้านของคุณ'),
              icon: const Icon(Icons.home),
            ),
        ],
      ),
    );
  }

  /// ปรับกล้องให้เห็นทุก Rider + บ้านพร้อมกัน
  void _fitAllMarkers() {
    if (_riderLocations.isEmpty && _receiverLocation == null) return;

    final allPoints = [
      ..._riderLocations.values,
      if (_receiverLocation != null) _receiverLocation!,
    ];

    // คำนวณขอบเขต (bounds)
    final latitudes = allPoints.map((p) => p.latitude);
    final longitudes = allPoints.map((p) => p.longitude);
    final center = LatLng(
      (latitudes.reduce((a, b) => a + b) / allPoints.length),
      (longitudes.reduce((a, b) => a + b) / allPoints.length),
    );
    _mapController.move(center, 12.5);
  }
}

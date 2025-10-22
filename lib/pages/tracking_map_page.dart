// 🎯 lib/pages/tracking_map_page.dart (Multi-Rider tracking for a receiver)

import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class TrackingMapPage extends StatefulWidget {
  final String receiverPhone; // ✅ ระบุตัวผู้รับ

  const TrackingMapPage({super.key, required this.receiverPhone});

  @override
  State<TrackingMapPage> createState() => _TrackingMapPageState();
}

class _TrackingMapPageState extends State<TrackingMapPage> {
  final MapController _mapController = MapController();
  StreamSubscription<QuerySnapshot>? _deliveriesSub;

  // เก็บตำแหน่ง Rider หลายคน (key = deliveryId)
  Map<String, LatLng> _riderLocations = {};
  // ตำแหน่งผู้รับ (อ่านจาก receiverAddress.lat/lng ของเอกสาร)
  LatLng? _receiverLocation;

  bool _hasMovedOnce = false; // เคลื่อนกล้องครั้งแรกเมื่อมีข้อมูล

  // ศูนย์เริ่มต้น (มหาสารคาม)
  final LatLng _initialCenter = const LatLng(16.1832, 103.3035);
  final double _initialZoom = 12.5;

  @override
  void initState() {
    super.initState();
    log('[TrackingMap] receiverPhone=${widget.receiverPhone}');
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
        .where('status', whereIn: ['assigned', 'picked']); // งานที่กำลังวิ่ง

    _deliveriesSub?.cancel();
    _deliveriesSub = query.snapshots().listen(
      (snapshot) {
        log('[TrackingMap] docs=${snapshot.docs.length}');
        final riders = <String, LatLng>{};
        LatLng? recv;

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;

          // 🛵 Rider location
          final gp = data['riderLocation'] as GeoPoint?;
          if (gp != null) {
            riders[doc.id] = LatLng(gp.latitude, gp.longitude);
          }

          // 🏠 Receiver location (ใช้ใบแรกที่มี)
          if (recv == null) {
            final ra = data['receiverAddress'] as Map<String, dynamic>?;
            final rlat = (ra?['lat'] as num?)?.toDouble();
            final rlng = (ra?['lng'] as num?)?.toDouble();
            if (rlat != null && rlng != null) {
              recv = LatLng(rlat, rlng);
            }
          }
        }

        if (!mounted) return;
        setState(() {
          _riderLocations = riders;
          _receiverLocation = recv;
        });

        if (!_hasMovedOnce) {
          final target = _riderLocations.values.isNotEmpty
              ? _riderLocations.values.first
              : (_receiverLocation ?? _initialCenter);
          _mapController.move(target, 14.5);
          _hasMovedOnce = true;
        }
      },
      onError: (e) {
        log('[TrackingMap] error: $e');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🧭 Markers
    final markers = <Marker>[
      // Riders (หลายคน)
      ..._riderLocations.entries.map((e) {
        return Marker(
          width: 40,
          height: 40,
          point: e.value,
          child: Tooltip(
            message: 'Rider ของงาน ${e.key.substring(0, 6)}',
            child: Image.asset(
              'assets/images/motorcycle_icon.png',
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.two_wheeler, size: 30, color: Colors.blue),
            ),
          ),
        );
      }),
      // Receiver (บ้านผู้รับ)
      if (_receiverLocation != null)
        Marker(
          width: 64,
          height: 64,
          point: _receiverLocation!,
          child: const Tooltip(
            message: 'ที่อยู่ของคุณ',
            child: Icon(Icons.home, color: Colors.green, size: 40),
          ),
        ),
    ];

    // 🔶 เส้นเชื่อมแต่ละ Rider → ผู้รับ
    final polylines = <Polyline>[
      if (_receiverLocation != null)
        ..._riderLocations.values.map(
          (p) => Polyline(points: [p, _receiverLocation!], strokeWidth: 4),
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
          // ✅ ใช้ผู้ให้บริการที่มีคีย์ เพื่อลดโอกาสโดนบล็อก
          TileLayer(
            urlTemplate:
                'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=66bb35dc3aad4f21b4b0de85b001cb0a',
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

  /// ปรับกล้องให้เห็นทุก Rider + บ้านพร้อมกันแบบง่าย ๆ
  void _fitAllMarkers() {
    final pts = <LatLng>[
      ..._riderLocations.values,
      if (_receiverLocation != null) _receiverLocation!,
    ];
    if (pts.isEmpty) return;

    final avgLat =
        pts.map((e) => e.latitude).reduce((a, b) => a + b) / pts.length;
    final avgLng =
        pts.map((e) => e.longitude).reduce((a, b) => a + b) / pts.length;

    _mapController.move(LatLng(avgLat, avgLng), 12.5);
  }
}

// 🎯 lib/pages/tracking_map_page.dart (ฉบับแก้ไขสมบูรณ์ + fixed _initialZoom)
import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'rider_detail_page.dart'; // Import Rider Detail Page

class TrackingMapPage extends StatefulWidget {
  final String receiverPhone;
  const TrackingMapPage({super.key, required this.receiverPhone});

  @override
  State<TrackingMapPage> createState() => _TrackingMapPageState();
}

class _TrackingMapPageState extends State<TrackingMapPage> {
  final MapController _mapController = MapController();
  StreamSubscription<QuerySnapshot>? _deliveriesSub;

  // เก็บข้อมูล Rider ต่อ deliveryId
  Map<String, Map<String, dynamic>> _riderData =
      {}; // { deliveryId: { latLng, riderId } }

  LatLng? _receiverLocation;
  bool _hasMovedOnce = false;

  // ตำแหน่ง/ซูมเริ่มต้น
  final LatLng _initialCenter = const LatLng(16.1832, 103.3035); // มหาสารคาม
  final double _initialZoom = 12.5; // ✅ เพิ่มกลับมา
  double _currentZoom = 12.5; // เก็บ zoom ปัจจุบัน

  @override
  void initState() {
    super.initState();
    log('[TrackingMap] initState receiverPhone=${widget.receiverPhone}');
    _listenDeliveriesToReceiver();
  }

  @override
  void dispose() {
    log('[TrackingMap] dispose');
    _deliveriesSub?.cancel();
    super.dispose();
  }

  void _listenDeliveriesToReceiver() {
    log(
      '[TrackingMap] Starting listener for receiver: ${widget.receiverPhone}',
    );
    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('receiverPhone', isEqualTo: widget.receiverPhone)
        .where('status', whereIn: ['assigned', 'picked']);

    _deliveriesSub?.cancel();
    _deliveriesSub = query.snapshots().listen(
      (snapshot) {
        log('[TrackingMap] Snapshot received: ${snapshot.docs.length} docs.');
        final currentRiderData = <String, Map<String, dynamic>>{};
        LatLng? recv;

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;

          final gp = data['riderLocation'] as GeoPoint?;
          final riderId = data['riderId'] as String?;
          if (gp != null && riderId != null && riderId.isNotEmpty) {
            final latLng = LatLng(gp.latitude, gp.longitude);
            currentRiderData[doc.id] = {'latLng': latLng, 'riderId': riderId};
            log('[TrackingMap] Rider for ${doc.id}: $riderId @ $latLng');
          }

          if (recv == null) {
            final ra = data['receiverAddress'] as Map<String, dynamic>?;
            final rlat = (ra?['lat'] as num?)?.toDouble();
            final rlng = (ra?['lng'] as num?)?.toDouble();
            if (rlat != null && rlng != null) {
              recv = LatLng(rlat, rlng);
              log('[TrackingMap] Receiver location: $recv');
            }
          }
        }

        if (!mounted) return;
        setState(() {
          _riderData = currentRiderData;
          _receiverLocation = recv;
        });
        log('[TrackingMap] State updated. Riders: ${_riderData.length}');

        if (!_hasMovedOnce) {
          final target = _riderData.values.isNotEmpty
              ? _riderData.values.first['latLng'] as LatLng
              : (_receiverLocation ?? _initialCenter);
          final zoomLevel = _riderData.values.isNotEmpty
              ? 14.5
              : _initialZoom; // ✅ ใช้ _initialZoom ได้แล้ว
          _mapController.move(target, zoomLevel);
          _currentZoom = zoomLevel;
          _hasMovedOnce = true;
        }
      },
      onError: (error) {
        log('[TrackingMap] Error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาดในการโหลดตำแหน่ง: $error')),
          );
          setState(() => _riderData = {});
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    log('[TrackingMap] Building UI. Rider count: ${_riderData.length}');
    final markers = <Marker>[
      // Markers ของ Rider (แตะเพื่อไปหน้า RiderDetailPage)
      ..._riderData.entries.map((entry) {
        final riderInfo = entry.value;
        final LatLng position = riderInfo['latLng'] as LatLng;
        final String riderId = riderInfo['riderId'] as String;

        return Marker(
          width: 40,
          height: 40,
          point: position,
          child: GestureDetector(
            onTap: () {
              log('[TrackingMap] Tap Rider: $riderId');
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RiderDetailPage(riderId: riderId),
                ),
              );
            },
            child: Tooltip(
              message: 'Rider ID: $riderId',
              child: Image.asset(
                'assets/images/motorcycle_icon.png',
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.two_wheeler, size: 30, color: Colors.blue),
              ),
            ),
          ),
        );
      }),
      // Marker บ้านผู้รับ
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

    return Scaffold(
      appBar: AppBar(title: const Text('ติดตาม Rider')),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _hasMovedOnce
              ? _mapController.camera.center
              : (_receiverLocation ?? _initialCenter),
          initialZoom: _currentZoom,
          onPositionChanged: (camera, hasGesture) {
            if (hasGesture && mounted) {
              _currentZoom = camera.zoom ?? _currentZoom;
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://tile.thunderforest.com/atlas/{z}/{x}/{y}.png?apikey=66bb35dc3aad4f21b4b0de85b001cb0a',
            userAgentPackageName: 'com.knnhub.deliver_app',
          ),
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution(
                'Maps © Thunderforest, Data © OpenStreetMap contributors',
              ),
            ],
            showFlutterMapAttribution: false,
          ),
          MarkerLayer(markers: markers),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_riderData.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: 'fitAll',
              onPressed: _fitAllMarkers,
              label: const Text('แสดงทั้งหมด'),
              icon: const Icon(Icons.zoom_out_map),
              tooltip: 'ปรับมุมมองให้เห็น Rider และบ้านของคุณ',
            ),
          const SizedBox(height: 8),
          if (_receiverLocation != null)
            FloatingActionButton.extended(
              heroTag: 'toReceiver',
              onPressed: () {
                _mapController.move(_receiverLocation!, 15.0);
                _currentZoom = 15.0;
              },
              label: const Text('ไปยังบ้าน'),
              icon: const Icon(Icons.home_outlined),
              tooltip: 'เลื่อนแผนที่ไปยังตำแหน่งบ้านของคุณ',
            ),
        ],
      ),
    );
  }

  void _fitAllMarkers() {
    log('[TrackingMap] Fitting map to all markers...');
    final pts = <LatLng>[
      ..._riderData.values.map((info) => info['latLng'] as LatLng),
      if (_receiverLocation != null) _receiverLocation!,
    ];

    if (pts.isEmpty) {
      log('[TrackingMap] No points. Move to initial.');
      _mapController.move(
        _initialCenter,
        _initialZoom,
      ); // ✅ ใช้ _initialZoom ได้แล้ว
      _currentZoom = _initialZoom;
      return;
    }
    if (pts.length == 1) {
      log('[TrackingMap] Single point: ${pts.first}');
      _mapController.move(pts.first, 15.0);
      _currentZoom = 15.0;
      return;
    }

    final bounds = LatLngBounds.fromPoints(pts);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
    );
  }
}

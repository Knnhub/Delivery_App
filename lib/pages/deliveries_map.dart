// 🎯 lib/pages/deliveries_map.dart
import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveriesMapPage extends StatefulWidget {
  const DeliveriesMapPage({super.key, required this.senderPhone});
  final String senderPhone;

  @override
  State<DeliveriesMapPage> createState() => _DeliveriesMapPageState();
}

class _DeliveriesMapPageState extends State<DeliveriesMapPage> {
  final MapController _mapController = MapController();
  StreamSubscription<QuerySnapshot>? _sub;

  // เก็บข้อมูลของงานที่กำลังวิ่ง (key = deliveryId)
  final Map<String, _DeliveryMarker> _markers = {};
  bool _hasMovedOnce = false;
  double _currentZoom = 12;

  // จุดตั้งต้น (มหาสารคาม)
  static const LatLng _initialCenter = LatLng(16.1832, 103.3035);

  @override
  void initState() {
    super.initState();
    _listenSenderRunningDeliveries();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listenSenderRunningDeliveries() {
    final q = FirebaseFirestore.instance
        .collection('deliveries')
        .where('senderId', isEqualTo: widget.senderPhone)
        .where('status', whereIn: ['assigned', 'picked']);

    _sub?.cancel();
    _sub = q.snapshots().listen((snap) {
      final next = <String, _DeliveryMarker>{};

      for (final d in snap.docs) {
        final data = d.data() as Map<String, dynamic>;

        // ตำแหน่งไรเดอร์
        final gp = data['riderLocation'] as GeoPoint?;
        // ตำแหน่งผู้รับ (เผื่อใช้เปิดแผนที่)
        final recv = (data['receiverAddress'] as Map<String, dynamic>?) ?? {};
        final rlat = (recv['lat'] as num?)?.toDouble();
        final rlng = (recv['lng'] as num?)?.toDouble();

        if (gp != null) {
          next[d.id] = _DeliveryMarker(
            deliveryId: d.id,
            riderPos: LatLng(gp.latitude, gp.longitude),
            status: (data['status'] as String?) ?? 'unknown',
            code: (data['code'] as String?) ?? d.id,
            riderId: (data['riderId'] as String?) ?? '',
            receiverName: (data['receiverName'] as String?) ?? '',
            receiverPhone: (data['receiverPhone'] as String?) ?? '',
            receiverAddress: (recv['address'] as String?) ?? '',
            receiverPos: (rlat != null && rlng != null)
                ? LatLng(rlat, rlng)
                : null,
          );
        }
      }

      if (!mounted) return;
      setState(
        () => _markers
          ..clear()
          ..addAll(next),
      );

      // ขยับกล้องครั้งแรกเมื่อมีหมุด
      if (!_hasMovedOnce && _markers.isNotEmpty) {
        _mapController.move(_markers.values.first.riderPos, 14.5);
        _currentZoom = 14.5;
        _hasMovedOnce = true;
      }
    }, onError: (e) => log('[DeliveriesMap] error: $e'));
  }

  @override
  Widget build(BuildContext context) {
    final riderMarkers = _markers.values.map((m) {
      return Marker(
        width: 40,
        height: 40,
        point: m.riderPos,
        child: GestureDetector(
          onTap: () => _openDeliveryBottomSheet(m),
          child: Tooltip(
            message:
                'รหัส: ${m.code.substring(0, 6)}… • สถานะ: ${m.status} • ไรเดอร์: ${m.riderId.isEmpty ? "-" : m.riderId}',
            child: Image.asset(
              'assets/images/motorcycle_icon.png',
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.two_wheeler, size: 28, color: Colors.blue),
            ),
          ),
        ),
      );
    }).toList();

    // (ตัวเลือก) แสดงหมุดบ้านผู้รับด้วยสีเขียวจาง ๆ
    final receiverMarkers = _markers.values
        .where((m) => m.receiverPos != null)
        .map((m) {
          return Marker(
            width: 40,
            height: 40,
            point: m.receiverPos!,
            child: Tooltip(
              message:
                  'ผู้รับ: ${m.receiverName.isEmpty ? m.receiverPhone : m.receiverName}',
              child: const Icon(Icons.home, size: 28, color: Colors.green),
            ),
          );
        })
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('พัสดุกำลังจัดส่ง (แผนที่รวม)')),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _initialCenter,
          initialZoom: _currentZoom,
          onPositionChanged: (pos, hasGesture) {
            if (hasGesture && pos.zoom != null) _currentZoom = pos.zoom!;
          },
        ),
        children: [
          // ใช้ OpenStreetMap (ไม่ต้องใช้ API key)
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.deliver_app',
          ),
          RichAttributionWidget(
            attributions: const [
              TextSourceAttribution('© OpenStreetMap contributors'),
            ],
            showFlutterMapAttribution: false,
          ),
          MarkerLayer(markers: [...receiverMarkers, ...riderMarkers]),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_markers.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: 'fitAll',
              onPressed: _fitAll,
              label: const Text('แสดงทั้งหมด'),
              icon: const Icon(Icons.zoom_out_map),
            ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'recenter',
            onPressed: () {
              if (_markers.isEmpty) {
                _mapController.move(_initialCenter, 12);
              } else {
                _mapController.move(_markers.values.first.riderPos, 14.5);
              }
            },
            label: const Text('กึ่งกลาง'),
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }

  void _fitAll() {
    final pts = <LatLng>[
      ..._markers.values.map((m) => m.riderPos),
      ..._markers.values
          .where((m) => m.receiverPos != null)
          .map((m) => m.receiverPos!),
    ];
    if (pts.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(pts);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  void _openDeliveryBottomSheet(_DeliveryMarker m) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('พัสดุ: ${m.code}'),
              subtitle: Text('สถานะ: ${m.status}'),
              trailing: Chip(
                label: Text(
                  m.riderId.isEmpty ? 'ไรเดอร์: -' : 'ไรเดอร์: ${m.riderId}',
                ),
              ),
            ),
            if (m.receiverAddress.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ผู้รับ: ${m.receiverName.isEmpty ? m.receiverPhone : m.receiverName}\n${m.receiverAddress}',
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.two_wheeler),
                    label: const Text('ตำแหน่งไรเดอร์'),
                    onPressed: () => _openExternalMap(
                      lat: m.riderPos.latitude,
                      lng: m.riderPos.longitude,
                      label: 'Rider ${m.riderId}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.home_outlined),
                    label: const Text('ตำแหน่งผู้รับ'),
                    onPressed: (m.receiverPos == null)
                        ? null
                        : () => _openExternalMap(
                            lat: m.receiverPos!.latitude,
                            lng: m.receiverPos!.longitude,
                            label:
                                'Receiver ${m.receiverName.isEmpty ? m.receiverPhone : m.receiverName}',
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('ซูมไปยังไรเดอร์'),
              onPressed: () {
                Navigator.pop(context);
                _mapController.move(m.riderPos, 16);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternalMap({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final encoded = Uri.encodeComponent(label ?? 'ตำแหน่ง');
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng($encoded)');
    final web = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    try {
      final ok = await launchUrl(geo, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(web, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่สามารถเปิดแผนที่ได้')),
          );
        }
      }
    }
  }
}

class _DeliveryMarker {
  _DeliveryMarker({
    required this.deliveryId,
    required this.riderPos,
    required this.status,
    required this.code,
    required this.riderId,
    required this.receiverName,
    required this.receiverPhone,
    required this.receiverAddress,
    required this.receiverPos,
  });

  final String deliveryId;
  final LatLng riderPos;
  final String status;
  final String code;
  final String riderId;

  final String receiverName;
  final String receiverPhone;
  final String receiverAddress;
  final LatLng? receiverPos;
}

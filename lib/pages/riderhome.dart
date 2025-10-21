import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliver_app/pages/profile.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'ridermap.dart'; // หน้าดูแผนที่ของงานที่รับแล้ว (มีอยู่เดิมในโปรเจกต์)

// -----------------------------
// Utilities
// -----------------------------
Future<bool> ensureLocationPermission() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    log('Location service disabled.');
    return false;
  }
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      log('Location permission denied.');
      return false;
    }
  }
  if (permission == LocationPermission.deniedForever) {
    log('Location permission denied forever.');
    return false;
  }
  return true;
}

String calculateDistanceText(LatLng? start, LatLng? end) {
  if (start == null || end == null) return 'N/A';
  final double distanceInMeters = const Distance().as(
    LengthUnit.Meter,
    start,
    end,
  );
  final double distanceInKm = distanceInMeters / 1000.0;
  return '${distanceInKm.toStringAsFixed(1)} km';
}

Color statusColor(String status) {
  switch (status) {
    case 'created':
      return Colors.blue;
    case 'assigned':
      return Colors.orange;
    case 'picked':
      return Colors.purple;
    case 'delivered':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

// -----------------------------
// Rider Home (Shell + Location updater service)
// -----------------------------
class RiderhomePage extends StatefulWidget {
  const RiderhomePage({super.key});

  @override
  State<RiderhomePage> createState() => _RiderhomePageState();
}

class _RiderhomePageState extends State<RiderhomePage> {
  int _selectedIndex = 0;
  String? phone;

  Timer? _locationUpdateTimer;
  String? _activeDeliveryId;
  StreamSubscription?
  _currentJobStatusSubscription; // เปลี่ยนชื่อเพื่อให้ชัดเจน
  bool _isLocationServiceRunning = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (phone == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        phone = args;
        log('Riderhome received phone: $phone');
        _checkForExistingActiveJob(); // Check for existing job on startup
      } else {
        log('Riderhome did not receive phone number.');
      }
    }
  }

  @override
  void dispose() {
    _stopLocationUpdates();
    super.dispose();
  }

  Future<void> _checkForExistingActiveJob() async {
    if (phone == null) return;
    try {
      final query = FirebaseFirestore.instance
          .collection('deliveries')
          .where('riderId', isEqualTo: phone)
          .where('status', whereIn: ['assigned', 'picked'])
          .limit(1);
      final snapshot = await query.get();
      if (snapshot.docs.isNotEmpty) {
        final activeDoc = snapshot.docs.first;
        log('Found existing active job on startup: ${activeDoc.id}');
        _startLocationUpdates(activeDoc.id); // Start updates if job exists
      } else {
        log('No existing active job found on startup.');
      }
    } catch (e) {
      log('Error checking for existing job: $e');
    }
  }

  void _startLocationUpdates(String deliveryId) {
    log('>>> Request to START location updates for delivery: $deliveryId');
    if (_isLocationServiceRunning && _activeDeliveryId == deliveryId) {
      log('Location updates already running for this delivery.');
      return;
    }
    _stopLocationUpdates();
    _activeDeliveryId = deliveryId;
    _isLocationServiceRunning = true;

    _ensureLocationPermission().then((granted) {
      if (!granted || !_isLocationServiceRunning) {
        log('Permission denied or service stopped before starting timer.');
        _stopLocationUpdates();
        return;
      }
      log('Permission granted. Starting timer...');
      _listenToCurrentJobStatus(deliveryId);
      _updateLocationCallback(null); // Initial update

      // --- ✨ แก้ไข Duration ตรงนี้ ---
      _locationUpdateTimer = Timer.periodic(
        const Duration(minutes: 10), // ✅ เปลี่ยนเป็น 10 นาที
        _updateLocationCallback,
      );
      // --------------------------------
      log('Location update timer started (every 10 minutes) for $deliveryId.');
    });
  }

  void _listenToCurrentJobStatus(String deliveryId) {
    _currentJobStatusSubscription?.cancel();
    _currentJobStatusSubscription = FirebaseFirestore.instance
        .collection('deliveries')
        .doc(deliveryId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!snapshot.exists || !_isLocationServiceRunning) {
              _stopLocationUpdates();
              return;
            }
            final data = snapshot.data();
            final status = data?['status'] as String?;
            log('Current job ($deliveryId) status update: $status');
            if (status != 'assigned' && status != 'picked') {
              log('Job status changed to $status. Stopping location updates.');
              _stopLocationUpdates();
            }
          },
          onError: (error) {
            log('Error listening to current job status: $error');
            _stopLocationUpdates();
          },
        );
    log('Started listening to status updates for $deliveryId.');
  }

  Future<void> _updateLocationCallback(Timer? timer) async {
    if (!_isLocationServiceRunning || _activeDeliveryId == null) {
      log(
        'Callback check: Service stopped or no active delivery. Cancelling timer.',
      );
      timer?.cancel();
      _isLocationServiceRunning = false;
      return;
    }
    log('Timer ticked for $_activeDeliveryId: Getting location...');
    try {
      bool permissionGranted = await _ensureLocationPermission();
      if (!permissionGranted) {
        log('Permission lost during update. Stopping.');
        _stopLocationUpdates();
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final currentLatLng = LatLng(position.latitude, position.longitude);
      log(
        'Rider Location: ${currentLatLng.latitude}, ${currentLatLng.longitude}',
      );

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('deliveries')
          .doc(_activeDeliveryId!)
          .update({
            'riderLocation': GeoPoint(
              currentLatLng.latitude,
              currentLatLng.longitude,
            ),
          });
      log('Firestore location updated successfully for $_activeDeliveryId.');
    } catch (e) {
      log('Error during location update callback: $e');
    }
  }

  void _stopLocationUpdates() {
    if (_isLocationServiceRunning ||
        _locationUpdateTimer != null ||
        _currentJobStatusSubscription != null) {
      log('>>> Stopping location updates for $_activeDeliveryId...');
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = null;
      _currentJobStatusSubscription?.cancel();
      _currentJobStatusSubscription = null; // Cancel listener too
      _activeDeliveryId = null;
      _isLocationServiceRunning = false;
      log('Location updates stopped.');
    }
  }

  Future<bool> _ensureLocationPermission() async {
    // ... (โค้ดเหมือนเดิม) ...
    bool serviceEnabled;
    LocationPermission permission;
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      log('Location service disabled.');
      return false;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        log('Location permission denied.');
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      log('Location permission denied forever.');
      return false;
    }
    return true;
  }

  void _onItemTapped(int index) {
    // if (index == 3) {
    //   // _buildTabNavigator(
    //   //         index: 3,
    //   //         root: ProfilePage(currentUserPhone: senderPhone),
    //   // )
    //   Navigator.ProfilePage(currentUserPhone: phone);
    //   return;
    // }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      NewDeliveriesPage(phone: phone),
      AssignedDeliveriesPage(phone: phone),
      RiderHistoryPage(phone: phone),
      ProfilePage(currentUserPhone: phone),
    ];
    // final titles = ['รายการใหม่', 'งานของฉัน', 'ประวัติ', 'โปรไฟล์'];

    return Scaffold(
      appBar: AppBar(
        // title: Text([_selectedIndex]),
        automaticallyImplyLeading: false,
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'รายการใหม่'),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_turned_in),
            label: 'งานของฉัน',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'ประวัติ'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'โปรไฟล์'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

// -----------------------------
// หน้ารายการพัสดุใหม่ (ยังไม่ถูก assign)
// -----------------------------
class NewDeliveriesPage extends StatefulWidget {
  final String? phone;
  const NewDeliveriesPage({super.key, this.phone});

  @override
  State<NewDeliveriesPage> createState() => _NewDeliveriesPageState();
}

class _NewDeliveriesPageState extends State<NewDeliveriesPage> {
  Future<void> _assignOrder(String deliveryId) async {
    if (widget.phone == null || widget.phone!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้')),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('deliveries')
          .doc(deliveryId)
          .update({
            'status': 'assigned',
            'riderId': widget.phone,
            'assignedAt': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('รับออเดอร์เรียบร้อยแล้ว')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deliveries')
          .where('status', isEqualTo: 'created')
          // .where('riderId', isNull: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }
        log(
          'Snapshot data received: HasData=${snapshot.hasData}, DocsCount=${snapshot.data?.docs.length}',
        );
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('ยังไม่มีรายการพัสดุ'));
        }

        final docs = snapshot.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;

            final senderAddress =
                (data['senderAddress'] as Map<String, dynamic>?) ?? {};
            final receiverAddress =
                (data['receiverAddress'] as Map<String, dynamic>?) ?? {};

            final senderLat = (senderAddress['lat'] as num?)?.toDouble();
            final senderLng = (senderAddress['lng'] as num?)?.toDouble();
            final receiverLat = (receiverAddress['lat'] as num?)?.toDouble();
            final receiverLng = (receiverAddress['lng'] as num?)?.toDouble();

            final senderLatLng = (senderLat != null && senderLng != null)
                ? LatLng(senderLat, senderLng)
                : null;
            final receiverLatLng = (receiverLat != null && receiverLng != null)
                ? LatLng(receiverLat, receiverLng)
                : null;
            final distanceString = calculateDistanceText(
              senderLatLng,
              receiverLatLng,
            );

            final senderAddressText =
                senderAddress['address'] as String? ?? 'N/A';
            final receiverAddressText =
                receiverAddress['address'] as String? ?? 'N/A';

            return Card(
              margin: const EdgeInsets.all(10.0),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'ผู้ส่ง: ${data['senderName'] ?? 'N/A'} (${data['senderId'] ?? ''})',
                          ),
                        ),
                        Chip(
                          avatar: Icon(
                            Icons.social_distance,
                            size: 18,
                            color: Theme.of(context).primaryColor,
                          ),
                          label: Text(distanceString),
                          backgroundColor: Theme.of(
                            context,
                          ).primaryColor.withOpacity(0.1),
                        ),
                      ],
                    ),
                    Text(
                      'รับจาก: $senderAddressText',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const Divider(height: 20),
                    Text(
                      'ผู้รับ: ${data['receiverName'] ?? 'N/A'} (${data['receiverPhone'] ?? ''})',
                    ),
                    Text(
                      'ส่งที่: $receiverAddressText',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ParcelDetailPage(
                                    deliveryId: doc.id,
                                    data: data,
                                  ),
                                ),
                              );
                            },
                            child: const Text('ดูรายละเอียด'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _assignOrder(doc.id),
                            child: const Text('รับงาน'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------
// หน้างานที่รับแล้วของฉัน
// -----------------------------
class AssignedDeliveriesPage extends StatelessWidget {
  final String? phone;
  const AssignedDeliveriesPage({super.key, this.phone});

  @override
  Widget build(BuildContext context) {
    if (phone == null || phone!.isEmpty) {
      return const Center(child: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deliveries')
          .where('riderId', isEqualTo: phone)
          .where('status', whereIn: ['assigned', 'picked'])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('คุณยังไม่มีงานที่รับ'));
        }

        final deliveries = snapshot.data!.docs;
        return ListView.builder(
          itemCount: deliveries.length,
          itemBuilder: (context, index) {
            final delivery = deliveries[index];
            final data = delivery.data() as Map<String, dynamic>;

            final senderAddress =
                (data['senderAddress'] as Map<String, dynamic>?) ?? {};
            final receiverAddress =
                (data['receiverAddress'] as Map<String, dynamic>?) ?? {};

            final senderLat = (senderAddress['lat'] as num?)?.toDouble();
            final senderLng = (senderAddress['lng'] as num?)?.toDouble();
            final receiverLat = (receiverAddress['lat'] as num?)?.toDouble();
            final receiverLng = (receiverAddress['lng'] as num?)?.toDouble();

            final senderLatLng = (senderLat != null && senderLng != null)
                ? LatLng(senderLat, senderLng)
                : null;
            final receiverLatLng = (receiverLat != null && receiverLng != null)
                ? LatLng(receiverLat, receiverLng)
                : null;
            final distanceString = calculateDistanceText(
              senderLatLng,
              receiverLatLng,
            );

            final senderAddressText =
                senderAddress['address'] as String? ?? 'ไม่มีข้อมูลที่อยู่';
            final receiverAddressText =
                receiverAddress['address'] as String? ?? 'ไม่มีข้อมูลที่อยู่';

            final status = (data['status'] as String?) ?? 'unknown';

            return Card(
              margin: const EdgeInsets.all(10.0),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ผู้ส่ง: ${data['senderName'] ?? 'ไม่มีชื่อ'}'),
                        Chip(
                          avatar: const Icon(
                            Icons.social_distance,
                            size: 18,
                            color: Colors.green,
                          ),
                          label: Text(distanceString),
                          backgroundColor: Colors.green.withOpacity(0.1),
                        ),
                      ],
                    ),
                    Text(
                      'จาก: $senderAddressText',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const Divider(height: 20),
                    Text('ผู้รับ: ${data['receiverName'] ?? 'ไม่มีชื่อ'}'),
                    Text(
                      'ไป: $receiverAddressText',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ParcelDetailPage(
                                  deliveryId: delivery.id,
                                  data: data,
                                ),
                              ),
                            );
                          },
                          child: const Text('ดูรายละเอียด'),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.map),
                          label: const Text('ดูแผนที่'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RiderMapPage(
                                  deliveryData: data,
                                  deliveryId: delivery.id,
                                ),
                              ),
                            );
                          },
                        ),
                        Chip(
                          label: Text('สถานะ: $status'),
                          backgroundColor: statusColor(status).withOpacity(0.2),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------
// History
// -----------------------------
class RiderHistoryPage extends StatelessWidget {
  final String? phone;
  const RiderHistoryPage({super.key, this.phone});

  @override
  Widget build(BuildContext context) {
    if (phone == null || phone!.isEmpty) {
      return const Center(child: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('deliveries')
          .where('riderId', isEqualTo: phone)
          .where('status', isEqualTo: 'delivered')
          .orderBy('deliveredAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('ยังไม่มีประวัติการส่ง'));
        }

        final docs = snapshot.data!.docs;
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final code = (data['code'] as String?) ?? doc.id;
            final to = (data['receiverAddress']?['address'] as String?) ?? '-';
            final deliveredAt = (data['deliveredAt'] as Timestamp?)?.toDate();
            return ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(code),
              subtitle: Text('ส่งที่: $to\nเมื่อ: ${deliveredAt ?? '-'}'),
              isThreeLine: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ParcelDetailPage(deliveryId: doc.id, data: data),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------
// Parcel Detail Page (ดูรายละเอียดพัสดุ)
// -----------------------------
class ParcelDetailPage extends StatelessWidget {
  final String deliveryId;
  final Map<String, dynamic> data;
  const ParcelDetailPage({
    super.key,
    required this.deliveryId,
    required this.data,
  });

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sender = (data['senderAddress'] as Map<String, dynamic>?) ?? {};
    final receiver = (data['receiverAddress'] as Map<String, dynamic>?) ?? {};

    return Scaffold(
      appBar: AppBar(
        title: Text('รายละเอียดพัสดุ ${data['code'] ?? deliveryId}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _row('สถานะ', (data['status'] as String?) ?? '-'),
          _row('ผู้ส่ง', (data['senderName'] as String?) ?? '-'),
          _row('เบอร์ผู้ส่ง', (data['senderId'] as String?) ?? '-'),
          _row('ผู้รับ', (data['receiverName'] as String?) ?? '-'),
          _row('เบอร์ผู้รับ', (data['receiverPhone'] as String?) ?? '-'),
          _row('รับจาก', (sender['address'] as String?) ?? '-'),
          _row('ส่งที่', (receiver['address'] as String?) ?? '-'),
          if (data['price'] != null) _row('ราคา', (data['price']).toString()),
          if (data['createdAt'] != null)
            _row(
              'สร้างเมื่อ',
              (data['createdAt'] is Timestamp)
                  ? (data['createdAt'] as Timestamp).toDate().toString()
                  : data['createdAt'].toString(),
            ),
        ],
      ),
    );
  }
}

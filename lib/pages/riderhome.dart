// 🎯 ไฟล์: lib/pages/riderhome_page.dart (ฉบับเต็ม - อัปเดตตามระยะทาง 10 เมตร + ปรับสี)

import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
// ตรวจสอบ path ของ profile.dart ให้ถูกต้อง
import 'package:deliver_app/pages/profile.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart'; // ✅ Import geolocator
import 'package:latlong2/latlong.dart';

import 'ridermap.dart'; // หน้าดูแผนที่ของงานที่รับแล้ว (มีอยู่เดิมในโปรเจกต์)
// Import หน้าอื่นๆ ที่ใช้ใน pages list (สร้างไฟล์เหล่านี้ถ้ายังไม่มี)
// (ตรวจสอบว่าไฟล์ rider_history_page.dart และ parcel_detail_page.dart มีอยู่จริง)
// (สมมติว่าไฟล์เหล่านี้ถูก import มาแล้ว หรือจะย้ายคลาสมาไว้ในไฟล์นี้ก็ได้)
// import 'rider_history_page.dart'; // (คลาส RiderHistoryPage อยู่ในไฟล์นี้แล้ว)
// import 'parcel_detail_page.dart'; // (คลาส ParcelDetailPage อยู่ในไฟล์นี้แล้ว)

// --- ✨ สี Theme ที่จะใช้ (สีม่วง) ---
const Color primaryColor = Color(0xFF8C78E8);
const Color backgroundColor = Color(0xFFE5E0FA);
const Color secondaryTextColor = Color(0xFFE9D5FF);
// --- จบสี Theme ---

// -----------------------------
// Utilities (ควรแยกไปไฟล์ใหม่ เช่น lib/utils/location_utils.dart)
// -----------------------------
Future<bool> ensureLocationPermission() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    log('[ensurePermission] Location service disabled.');
    return false;
  }
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    log('[ensurePermission] Permission denied, requesting...');
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      log('[ensurePermission] Permission denied again.');
      return false;
    }
  }
  if (permission == LocationPermission.deniedForever) {
    log('[ensurePermission] Permission denied forever.');
    return false;
  }
  log('[ensurePermission] Location permission granted.');
  return true; // ได้รับอนุญาต
}

// -----------------------------
// Utilities (ควรแยกไปไฟล์ใหม่ เช่น lib/utils/map_utils.dart)
// -----------------------------
String calculateDistanceText(LatLng? start, LatLng? end) {
  if (start == null || end == null) return 'N/A';
  try {
    final double distanceInMeters = const Distance().as(
      LengthUnit.Meter,
      start,
      end,
    );
    final double distanceInKm = distanceInMeters / 1000.0;
    return '${distanceInKm.toStringAsFixed(1)} km';
  } catch (e) {
    log("Error calculating distance: $e");
    return 'Error';
  }
}

// -----------------------------
// Utilities (ควรแยกไปไฟล์ใหม่ เช่น lib/utils/ui_utils.dart) - ปรับสีเขียวเป็นสีม่วง
// -----------------------------
Color statusColor(String status) {
  switch (status) {
    case 'created':
      return Colors.blue.shade600;
    case 'assigned':
      return Colors.orange.shade700;
    case 'picked':
      return Colors.purple.shade600; // อาจจะใช้สีม่วงเข้มกว่านี้
    case 'delivered':
      // return Colors.green.shade700; // <<< เดิม
      return primaryColor; // <<< เปลี่ยนเป็นสีม่วงหลัก
    case 'canceled':
      return Colors.red.shade700;
    default:
      return Colors.grey.shade600;
  }
}

Color statusBackgroundColor(String status) {
  switch (status) {
    case 'created':
      return Colors.blue.shade50;
    case 'assigned':
      return Colors.orange.shade50;
    case 'picked':
      return Colors.purple.shade50;
    case 'delivered':
      // return Colors.green.shade50; // <<< เดิม
      return primaryColor.withOpacity(0.1); // <<< เปลี่ยนเป็นสีม่วงอ่อนๆ
    case 'canceled':
      return Colors.red.shade50;
    default:
      return Colors.grey.shade100;
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
  String? phone; // เบอร์โทร Rider (ทำหน้าที่เป็น ID)

  // --- ✨ State สำหรับ Location Update ตามระยะทาง ✨ ---
  StreamSubscription<Position>?
  _positionStreamSubscription; // ใช้ Stream Subscription
  String? _activeDeliveryId; // ID งานที่กำลังทำ
  StreamSubscription<DocumentSnapshot>?
  _currentJobStatusSubscription; // Listener สถานะงานปัจจุบัน (ใช้ DocumentSnapshot)
  bool _isLocationServiceRunning = false; // สถานะการทำงานของ service
  LatLng? _lastReportedPosition; // ตำแหน่งล่าสุดที่ส่ง (ป้องกันส่งซ้ำ)
  // --- จบ State ---

  @override
  void initState() {
    super.initState();
    log('[RiderHome] initState');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    log('[RiderHome] didChangeDependencies');
    if (phone == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        phone = args;
        log('[RiderHome] Received phone: $phone');
        _checkForExistingActiveJob();
      } else {
        log('[RiderHome] Did not receive a valid phone number.');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('เกิดข้อผิดพลาด: ไม่พบข้อมูล Rider'),
              ),
            );
            // Consider navigating back to login
            // Navigator.of(context).pushReplacementNamed('/login');
          }
        });
      }
    }
  }

  @override
  void dispose() {
    log('[RiderHome] dispose');
    _stopLocationUpdates();
    super.dispose();
  }

  Future<void> _checkForExistingActiveJob() async {
    log('[RiderHome] Checking for existing active job...');
    if (phone == null || phone!.isEmpty) {
      log('[RiderHome] Cannot check for job, phone is null or empty.');
      return;
    }
    try {
      final query = FirebaseFirestore.instance
          .collection('deliveries')
          .where('riderId', isEqualTo: phone)
          .where('status', whereIn: ['assigned', 'picked'])
          .limit(1);

      final snapshot = await query.get();

      if (mounted && snapshot.docs.isNotEmpty) {
        final activeDoc = snapshot.docs.first;
        log(
          '[RiderHome] Found existing active job on startup: ${activeDoc.id}',
        );
        _startLocationUpdates(activeDoc.id);
      } else {
        log('[RiderHome] No existing active job found on startup.');
      }
    } catch (e) {
      log('[RiderHome] Error checking for existing job: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการตรวจสอบงาน: $e')),
        );
      }
    }
  }

  void _startLocationUpdates(String deliveryId) {
    log(
      '[RiderHome] >>> Request START location updates (distance based) for: $deliveryId',
    );
    if (_isLocationServiceRunning && _activeDeliveryId == deliveryId) {
      log('[RiderHome] Location stream already running for this delivery.');
      return;
    }

    _stopLocationUpdates();

    _activeDeliveryId = deliveryId;
    _isLocationServiceRunning = true;
    _lastReportedPosition = null;

    ensureLocationPermission().then((granted) {
      if (!granted || !_isLocationServiceRunning || !mounted) {
        log(
          '[RiderHome] Permission denied or service stopped before starting stream.',
        );
        _stopLocationUpdates();
        if (mounted && !granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง')),
          );
        }
        return;
      }

      log('[RiderHome] Permission granted. Starting location stream...');
      _listenToCurrentJobStatus(deliveryId);

      _positionStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            (Position position) {
              log('[RiderHome] Position stream update received.');
              if (mounted) {
                _handlePositionUpdate(position);
              }
            },
            onError: (error) {
              log('[RiderHome] Error getting position stream: $error');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ข้อผิดพลาด Stream ตำแหน่ง: $error')),
                );
                _stopLocationUpdates();
              }
            },
            onDone: () {
              log('[RiderHome] Position stream is done.');
              if (_isLocationServiceRunning && mounted) {
                log(
                  '[RiderHome] Position stream closed unexpectedly. Stopping service.',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'การติดตามตำแหน่งหยุดทำงาน โปรดลองรับงานใหม่',
                    ),
                  ),
                );
                _stopLocationUpdates();
              }
            },
            cancelOnError: true,
          );

      log('[RiderHome] Location stream listener started for $deliveryId.');
      _getInitialPositionAndUpdate();
    });
  }

  Future<void> _getInitialPositionAndUpdate() async {
    log('[RiderHome] Getting initial position...');
    try {
      bool permissionGranted = await ensureLocationPermission();
      if (!permissionGranted || !_isLocationServiceRunning || !mounted) return;

      Position initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      log(
        '[RiderHome] Got initial position: ${initialPosition.latitude}, ${initialPosition.longitude}',
      );
      if (_isLocationServiceRunning && mounted) {
        _handlePositionUpdate(initialPosition, isInitial: true);
      }
    } catch (e) {
      log("[RiderHome] Error getting initial position: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถดึงตำแหน่งเริ่มต้นได้: $e')),
        );
      }
    }
  }

  void _handlePositionUpdate(Position position, {bool isInitial = false}) {
    if (!_isLocationServiceRunning || _activeDeliveryId == null || !mounted) {
      log(
        '[RiderHome] Received position update but conditions not met (service stopped, no active job, or not mounted).',
      );
      return;
    }

    final currentLatLng = LatLng(position.latitude, position.longitude);
    log(
      '[RiderHome] ${isInitial ? "Initial" : "Stream"} Position Update Handled: Lat=${currentLatLng.latitude}, Lng=${currentLatLng.longitude}, Acc=${position.accuracy}m',
    );

    const double minDistanceThreshold = 1.0;
    if (!isInitial && _lastReportedPosition != null) {
      double distance = const Distance().as(
        LengthUnit.Meter,
        _lastReportedPosition!,
        currentLatLng,
      );
      if (distance <= minDistanceThreshold) {
        log(
          '[RiderHome] Position change ($distance m) too small. Skipping Firestore update.',
        );
        return;
      }
    }

    FirebaseFirestore.instance
        .collection('deliveries')
        .doc(_activeDeliveryId!)
        .update({
          'riderLocation': GeoPoint(
            currentLatLng.latitude,
            currentLatLng.longitude,
          ),
          'riderLocationTimestamp': FieldValue.serverTimestamp(),
          'riderLocationAccuracy': position.accuracy,
        })
        .then((_) {
          log(
            '[RiderHome] Firestore location updated successfully for $_activeDeliveryId.',
          );
          _lastReportedPosition = currentLatLng;
        })
        .catchError((error) {
          log(
            '[RiderHome] Error updating Firestore location for $_activeDeliveryId: $error',
          );
          // Consider minimal feedback to avoid spamming the user
        });
  }

  void _listenToCurrentJobStatus(String deliveryId) {
    _currentJobStatusSubscription?.cancel();
    log('[RiderHome] Starting to listen job status for $deliveryId');
    _currentJobStatusSubscription = FirebaseFirestore.instance
        .collection('deliveries')
        .doc(deliveryId)
        .snapshots()
        .listen(
          (DocumentSnapshot snapshot) {
            if (!mounted || !_isLocationServiceRunning) {
              log(
                '[RiderHome] Job Status Listener: Not mounted or service stopped. Stopping updates.',
              );
              _stopLocationUpdates();
              return;
            }
            if (!snapshot.exists) {
              log(
                '[RiderHome] Job Status Listener: Delivery document $deliveryId not found. Stopping updates.',
              );
              _stopLocationUpdates();
              return;
            }

            final data = snapshot.data() as Map<String, dynamic>?;
            final status = data?['status'] as String?;
            log(
              '[RiderHome] Job Status Listener: Current job ($deliveryId) status update: $status',
            );

            if (status != 'assigned' && status != 'picked') {
              log(
                '[RiderHome] Job Status Listener: Job status changed to $status. Stopping location updates.',
              );
              _stopLocationUpdates();
            }
          },
          onError: (error) {
            log(
              '[RiderHome] Job Status Listener: Error listening to current job status ($deliveryId): $error',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('เกิดข้อผิดพลาดในการติดตามสถานะงาน: $error'),
                ),
              );
              _stopLocationUpdates();
            }
          },
          onDone: () {
            log('[RiderHome] Job status stream for $deliveryId is done.');
            if (mounted && _isLocationServiceRunning) {
              _stopLocationUpdates();
            }
          },
          cancelOnError: true,
        );
  }

  void _stopLocationUpdates() {
    bool wasRunning = _isLocationServiceRunning;
    if (wasRunning ||
        _positionStreamSubscription != null ||
        _currentJobStatusSubscription != null) {
      log(
        '[RiderHome] >>> Stopping location updates for $_activeDeliveryId...',
      );

      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      log('[RiderHome] Position stream subscription canceled.');

      _currentJobStatusSubscription?.cancel();
      _currentJobStatusSubscription = null;
      log('[RiderHome] Job status subscription canceled.');

      _activeDeliveryId = null;
      _isLocationServiceRunning = false;
      _lastReportedPosition = null;

      log('[RiderHome] Location updates stopped completely.');
    } else {
      log('[RiderHome] Stop location updates called, but nothing was running.');
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    void Function(String) startUpdatesCallback = _startLocationUpdates;

    final pages = <Widget>[
      NewDeliveriesPage(phone: phone, onAssignSuccess: startUpdatesCallback),
      AssignedDeliveriesPage(phone: phone),
      RiderHistoryPage(phone: phone),
      ProfilePage(currentUserPhone: phone, isRider: true),
    ];
    final titles = ['รายการใหม่', 'งานของฉัน', 'ประวัติ', 'โปรไฟล์'];

    log('[RiderHome] Building UI with selectedIndex: $_selectedIndex');

    return Scaffold(
      backgroundColor: backgroundColor, // <<< ตั้งสีพื้นหลัง Scaffold
      appBar: AppBar(
        title: Text(
          titles[_selectedIndex],
          style: TextStyle(color: Colors.white), // <<< สีขาว
        ),
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: primaryColor, // <<< สีม่วงหลัก
        foregroundColor: Colors.white, // <<< สีขาวสำหรับไอคอน (ถ้ามี)
        elevation: 0, // <<< เอาเงาออก
      ),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt_outlined),
            activeIcon: Icon(Icons.list_alt),
            label: 'รายการใหม่',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_turned_in_outlined),
            activeIcon: Icon(Icons.assignment_turned_in),
            label: 'งานของฉัน',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_outlined),
            activeIcon: Icon(Icons.history),
            label: 'ประวัติ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'โปรไฟล์',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: primaryColor, // <<< สีพื้นหลังม่วง
        selectedItemColor: Colors.white, // <<< สีไอคอน/Label ที่เลือก (สีขาว)
        unselectedItemColor: Colors.white.withOpacity(
          0.7,
        ), // <<< สีไอคอน/Label ที่ไม่ได้เลือก (ขาวจางๆ)
        showUnselectedLabels: true,
        elevation: 0, // <<< เอาเงาออก
      ),
    );
  }
} // End _RiderhomePageState

// =========================================================================
// ========================== Sub-Pages (Widgets) ==========================
// =========================================================================

// -----------------------------
// หน้ารายการพัสดุใหม่ (จำเป็นต้องรับ onAssignSuccess)
// -----------------------------
class NewDeliveriesPage extends StatefulWidget {
  final String? phone; // Rider's phone (ID)
  final void Function(String deliveryId)? onAssignSuccess;

  const NewDeliveriesPage({super.key, this.phone, this.onAssignSuccess});

  @override
  State<NewDeliveriesPage> createState() => _NewDeliveriesPageState();
}

class _NewDeliveriesPageState extends State<NewDeliveriesPage> {
  Future<void> _assignOrder(String deliveryId) async {
    if (widget.phone == null || widget.phone!.isEmpty) {
      log('[NewDeliveries] Cannot assign order: Rider phone is missing.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้')),
        );
      }
      return;
    }
    log(
      '[NewDeliveries] Attempting to assign order $deliveryId to rider ${widget.phone}',
    );
    try {
      await FirebaseFirestore.instance
          .collection('deliveries')
          .doc(deliveryId)
          .update({
            'status': 'assigned',
            'riderId': widget.phone,
            'assignedAt': FieldValue.serverTimestamp(),
          });

      log('[NewDeliveries] Order $deliveryId assigned successfully.');
      widget.onAssignSuccess?.call(deliveryId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รับออเดอร์เรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      log('[NewDeliveries] Error assigning order $deliveryId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการรับออเดอร์: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    log('[NewDeliveries] Building UI.');
    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('status', isEqualTo: 'created')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          log('[NewDeliveries] Stream waiting...');
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          );
        }
        if (snapshot.hasError) {
          log('[NewDeliveries] Stream error: ${snapshot.error}');
          if (snapshot.error.toString().contains('FAILED_PRECONDITION')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Firestore index required. Please create the index in Firebase Console: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }
        final docs = snapshot.data?.docs ?? [];
        log('[NewDeliveries] Stream received data: ${docs.length} documents.');
        if (docs.isEmpty) {
          return const Center(child: Text('ยังไม่มีรายการพัสดุใหม่'));
        }

        return RefreshIndicator(
          color: primaryColor,
          backgroundColor: Colors.white,
          onRefresh: () async {
            log('[NewDeliveries] Refresh triggered.');
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final senderAddressMap =
                  data['senderAddress'] as Map<String, dynamic>? ?? {};
              final receiverAddressMap =
                  data['receiverAddress'] as Map<String, dynamic>? ?? {};
              final senderLat = (senderAddressMap['lat'] as num?)?.toDouble();
              final senderLng = (senderAddressMap['lng'] as num?)?.toDouble();
              final receiverLat = (receiverAddressMap['lat'] as num?)
                  ?.toDouble();
              final receiverLng = (receiverAddressMap['lng'] as num?)
                  ?.toDouble();
              final senderLatLng = (senderLat != null && senderLng != null)
                  ? LatLng(senderLat, senderLng)
                  : null;
              final receiverLatLng =
                  (receiverLat != null && receiverLng != null)
                  ? LatLng(receiverLat, receiverLng)
                  : null;
              final distanceString = calculateDistanceText(
                senderLatLng,
                receiverLatLng,
              );
              final senderAddressText =
                  senderAddressMap['address'] as String? ?? 'N/A';
              final receiverAddressText =
                  receiverAddressMap['address'] as String? ?? 'N/A';
              final senderName = data['senderName'] as String? ?? 'N/A';
              final senderId = data['senderId'] as String? ?? '';
              final receiverName = data['receiverName'] as String? ?? 'N/A';
              final receiverPhone = data['receiverPhone'] as String? ?? '';

              return Card(
                color: Colors.white,
                surfaceTintColor: Colors.white,
                margin: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 6.0,
                ),
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'ผู้ส่ง: $senderName (${senderId.isNotEmpty ? senderId : '-'})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Chip(
                            avatar: Icon(
                              Icons.route_outlined,
                              size: 16,
                              color: primaryColor,
                            ),
                            label: Text(
                              distanceString,
                              style: TextStyle(
                                fontSize: 12,
                                color: primaryColor,
                              ),
                            ),
                            backgroundColor: primaryColor.withOpacity(0.1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            visualDensity: VisualDensity.compact,
                            side: BorderSide.none,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'รับจาก: $senderAddressText',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Divider(
                        height: 24,
                        thickness: 0.5,
                        color: Colors.grey.shade300,
                      ),
                      Text(
                        'ผู้รับ: $receiverName (${receiverPhone.isNotEmpty ? receiverPhone : '-'})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ส่งที่: $receiverAddressText',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.info_outline, size: 18),
                              label: const Text('รายละเอียด'),
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
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: primaryColor,
                                ), // <<< สีขอบม่วง
                                foregroundColor:
                                    primaryColor, // <<< สีตัวอักษร/ไอคอนม่วง
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(
                                Icons.motorcycle_outlined,
                                size: 18,
                              ),
                              label: const Text('รับงาน'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    primaryColor, // <<< สีพื้นหลังม่วง
                                foregroundColor:
                                    Colors.white, // <<< สีตัวอักษร/ไอคอนขาว
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              onPressed: () => _assignOrder(doc.id),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
} // End _NewDeliveriesPageState

// -----------------------------
// หน้างานที่รับแล้วของฉัน
// -----------------------------
class AssignedDeliveriesPage extends StatelessWidget {
  final String? phone; // Rider's phone (ID)
  const AssignedDeliveriesPage({super.key, this.phone});

  @override
  Widget build(BuildContext context) {
    if (phone == null || phone!.isEmpty) {
      return const Center(child: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้'));
    }

    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('riderId', isEqualTo: phone)
        .where('status', whereIn: ['assigned', 'picked'])
        .orderBy('assignedAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          );
        }
        if (snapshot.hasError) {
          log('[AssignedDeliveries] Stream error: ${snapshot.error}');
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }
        final deliveries = snapshot.data?.docs ?? [];
        if (deliveries.isEmpty) {
          return const Center(child: Text('คุณยังไม่มีงานที่กำลังดำเนินการ'));
        }

        return ListView.builder(
          itemCount: deliveries.length,
          itemBuilder: (context, index) {
            final delivery = deliveries[index];
            final data = delivery.data() as Map<String, dynamic>;

            final senderAddressMap =
                data['senderAddress'] as Map<String, dynamic>? ?? {};
            final receiverAddressMap =
                data['receiverAddress'] as Map<String, dynamic>? ?? {};
            final senderName = data['senderName'] as String? ?? 'N/A';
            final receiverName = data['receiverName'] as String? ?? 'N/A';
            final senderAddressText =
                senderAddressMap['address'] as String? ?? 'N/A';
            final receiverAddressText =
                receiverAddressMap['address'] as String? ?? 'N/A';
            final status = data['status'] as String? ?? 'unknown';

            final senderLat = (senderAddressMap['lat'] as num?)?.toDouble();
            final senderLng = (senderAddressMap['lng'] as num?)?.toDouble();
            final receiverLat = (receiverAddressMap['lat'] as num?)?.toDouble();
            final receiverLng = (receiverAddressMap['lng'] as num?)?.toDouble();
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

            return Card(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              margin: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'งาน ID: ${delivery.id.substring(0, 6)}...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        _StatusChipSmall(status: status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'รับจาก: $senderName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      senderAddressText,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                    Divider(
                      height: 24,
                      thickness: 0.5,
                      color: Colors.grey.shade300,
                    ),
                    Text(
                      'ส่งให้: $receiverName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      receiverAddressText,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Colors.grey.shade700,
                            ),
                            label: Text(
                              'รายละเอียด',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
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
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.grey.shade100,
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(
                              Icons.map_outlined,
                              size: 18,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'ดูแผนที่',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor, // <<< สีม่วง
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
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
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          avatar: Icon(
                            Icons.route_outlined,
                            size: 16,
                            color: Colors.grey.shade700, // <<< สีเทา
                          ),
                          label: Text(
                            distanceString,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700, // <<< สีเทา
                            ),
                          ),
                          backgroundColor:
                              Colors.grey.shade100, // <<< สีพื้นหลังเทาอ่อน
                          side: BorderSide(
                            color: Colors.grey.shade300,
                          ), // <<< สีขอบเทาอ่อน
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          visualDensity: VisualDensity.compact,
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
} // End AssignedDeliveriesPage

// -----------------------------
// History (ปรับสี Icon และ Chip และ Card)
// -----------------------------
class RiderHistoryPage extends StatelessWidget {
  final String? phone;
  const RiderHistoryPage({super.key, this.phone});

  @override
  Widget build(BuildContext context) {
    if (phone == null || phone!.isEmpty) {
      return const Center(child: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้'));
    }

    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('riderId', isEqualTo: phone)
        .where('status', whereIn: ['delivered', 'canceled'])
        .orderBy('updatedAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          );
        }
        if (snapshot.hasError) {
          log('[RiderHistory] Stream error: ${snapshot.error}');
          if (snapshot.error.toString().contains('FAILED_PRECONDITION')) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Firestore index required. Please create the index in Firebase Console: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('ยังไม่มีประวัติการส่ง'));
        }

        // --- ✨ เปลี่ยน ListView.separated เป็น ListView.builder + padding ---
        return ListView.builder(
          padding: const EdgeInsets.all(12.0), // <<< เพิ่ม Padding รอบ ListView
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;

            final code = data['code'] as String? ?? doc.id.substring(0, 6);
            final to = data['receiverAddress']?['address'] as String? ?? '-';
            final status = data['status'] as String? ?? 'unknown';
            final Timestamp? timestamp =
                data['deliveredAt'] as Timestamp? ??
                data['canceledAt'] as Timestamp? ??
                data['updatedAt'] as Timestamp?;
            final DateTime? completedDate = timestamp?.toDate();

            String formatTimestamp(DateTime? dt) {
              if (dt == null) return '-';
              final d = dt.toLocal();
              return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
            }

            // --- ✨ สร้าง Card layout ใหม่ ---
            return Card(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.only(
                bottom: 8,
              ), // <<< ระยะห่างระหว่าง Card
              child: InkWell(
                // <<< เพิ่ม InkWell เพื่อให้กดได้
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ParcelDetailPage(deliveryId: doc.id, data: data),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- แถวบนสุด (Icon, ID, Status) ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                status == 'delivered'
                                    ? Icons.check_circle_outline
                                    : Icons.cancel_outlined,
                                color: status == 'delivered'
                                    ? primaryColor
                                    : Colors.red,
                                size: 20, // <<< ขนาดไอคอน
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ID: $code',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          _StatusChipSmall(status: status), // Chip สถานะ
                        ],
                      ),
                      const SizedBox(height: 12), // <<< ระยะห่าง
                      // --- ที่อยู่ ---
                      Text(
                        'ส่งที่: $to',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4), // <<< ระยะห่าง
                      // --- เวลา ---
                      Text(
                        'เมื่อ: ${formatTimestamp(completedDate)}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            // --- จบ Card layout ใหม่ ---
          },
        );
      },
    );
  }
} // End RiderHistoryPage

// -----------------------------
// Parcel Detail Page (ปรับสี Icon ใน _row)
// -----------------------------
class ParcelDetailPage extends StatelessWidget {
  final String deliveryId;
  final Map<String, dynamic> data;
  const ParcelDetailPage({
    super.key,
    required this.deliveryId,
    required this.data,
  });

  Widget _row(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: primaryColor, size: 20), // <<< ใช้ primaryColor
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? '-' : value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate().toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return ts?.toString() ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    final senderAddr = data['senderAddress'] as Map<String, dynamic>? ?? {};
    final receiverAddr = data['receiverAddress'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'รายละเอียด #${data['code'] ?? deliveryId.substring(0, 6)}',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: _StatusChipSmall(status: data['status'] ?? 'unknown'),
          ),
        ],
      ),
      backgroundColor: backgroundColor,
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section: Sender Info
          Card(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ข้อมูลผู้ส่ง',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _row(
                    context,
                    Icons.person_outline,
                    'ชื่อผู้ส่ง',
                    data['senderName'] ?? '-',
                  ),
                  _row(
                    context,
                    Icons.phone_outlined,
                    'เบอร์โทรผู้ส่ง',
                    data['senderId'] ?? '-',
                  ),
                  _row(
                    context,
                    Icons.location_on_outlined,
                    'ที่อยู่ผู้ส่ง',
                    senderAddr['address'] ?? '-',
                  ),
                ],
              ),
            ),
          ),
          // Section: Receiver Info
          Card(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ข้อมูลผู้รับ',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _row(
                    context,
                    Icons.person_pin_circle_outlined,
                    'ชื่อผู้รับ',
                    data['receiverName'] ?? '-',
                  ),
                  _row(
                    context,
                    Icons.phone_android_outlined,
                    'เบอร์โทรผู้รับ',
                    data['receiverPhone'] ?? '-',
                  ),
                  _row(
                    context,
                    Icons.pin_drop_outlined,
                    'ที่อยู่ผู้รับ',
                    receiverAddr['address'] ?? '-',
                  ),
                ],
              ),
            ),
          ),
          // Section: Item Details
          Card(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'รายการสินค้า (${items.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Text('ไม่มีรายการสินค้า')
                  else
                    ...items.map((item) {
                      final itemData = item as Map<String, dynamic>? ?? {};
                      final imageUrl = itemData['imageUrl'] as String?;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrl, // <<< ใส่ตัวแปร imageUrl
                                    height: 150,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                          if (loadingProgress == null)
                                            return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              value:
                                                  loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                            .cumulativeBytesLoaded /
                                                        loadingProgress
                                                            .expectedTotalBytes!
                                                  : null,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    primaryColor,
                                                  ), // <<< ปรับสี Loading
                                            ),
                                          );
                                        },
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              height: 150,
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Icon(
                                                  Icons.broken_image,
                                                  color: Colors.grey.shade400,
                                                  size: 40,
                                                ),
                                              ),
                                            ),
                                  ),
                                ),
                              ),
                            Text(
                              itemData['name'] ?? '-',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'จำนวน: ${itemData['qty'] ?? '-'} ${itemData['weight'] != null ? '• น้ำหนัก: ${itemData['weight']} กก.' : ''}',
                            ),
                            if (itemData['note'] != null &&
                                itemData['note'].toString().isNotEmpty)
                              Text('หมายเหตุ: ${itemData['note']}'),
                            if (items.indexOf(item) <
                                items.length -
                                    1) // <<< เพิ่มเงื่อนไขเช็คว่าไม่ใช่ item สุดท้าย
                              const Divider(
                                height: 16,
                              ), // <<< ย้าย Divider มาไว้ตรงนี้
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          // Section: Timestamps
          Card(
            color: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ข้อมูลเวลา',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _row(
                    context,
                    Icons.timer_outlined,
                    'สร้างเมื่อ',
                    _formatTimestamp(data['createdAt']),
                  ),
                  if (data['assignedAt'] != null)
                    _row(
                      context,
                      Icons.assignment_ind_outlined,
                      'มอบหมายเมื่อ',
                      _formatTimestamp(data['assignedAt']),
                    ),
                  if (data['pickedAt'] != null)
                    _row(
                      context,
                      Icons.inventory_2_outlined,
                      'รับของเมื่อ',
                      _formatTimestamp(data['pickedAt']),
                    ),
                  if (data['deliveredAt'] != null)
                    _row(
                      context,
                      Icons.check_circle_outline,
                      'ส่งสำเร็จเมื่อ',
                      _formatTimestamp(data['deliveredAt']),
                    ),
                  if (data['canceledAt'] != null)
                    _row(
                      context,
                      Icons.cancel_outlined,
                      'ยกเลิกเมื่อ',
                      _formatTimestamp(data['canceledAt']),
                    ),
                ],
              ),
            ),
          ),
          // Proof Images (Optional styling)
          if (data['pickupProofImageUrl'] != null) ...[
            const Text(
              'หลักฐานการรับของ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ClipRRect(
                // <<< เพิ่ม ClipRRect
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  data['pickupProofImageUrl'],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200, // <<< จำกัดความสูง
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.grey.shade200,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            primaryColor,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: Colors.grey.shade200,
                    child: Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.grey.shade400,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (data['deliveryProofImageUrl'] != null) ...[
            const Text(
              'หลักฐานการส่งของ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: ClipRRect(
                // <<< เพิ่ม ClipRRect
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  data['deliveryProofImageUrl'],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200, // <<< จำกัดความสูง
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.grey.shade200,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            primaryColor,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: Colors.grey.shade200,
                    child: Center(
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.grey.shade400,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
} // End ParcelDetailPage

// -----------------------------
// Helper Widget for Status Chip (Small version)
// -----------------------------
class _StatusChipSmall extends StatelessWidget {
  const _StatusChipSmall({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    String label() {
      switch (status) {
        case 'created':
          return 'รอไรเดอร์รับงาน'; // <<< เปลี่ยนข้อความ
        case 'assigned':
          return 'ไรเดอร์รับงานแล้ว'; // <<< เปลี่ยนข้อความ
        case 'picked':
          return 'รับของแล้ว';
        case 'delivered':
          return 'ส่งสำเร็จ';
        case 'canceled':
          return 'ยกเลิก';
        default:
          return status;
      }
    }

    return Chip(
      label: Text(
        label(),
        style: TextStyle(
          fontSize: 11,
          color: statusColor(
            status,
          ), // <<< ใช้สีจาก utility function ที่แก้ไขแล้ว
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: statusBackgroundColor(
        status,
      ), // <<< ใช้สีพื้นหลังจาก utility function ที่แก้ไขแล้ว
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

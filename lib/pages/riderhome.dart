// 🎯 ไฟล์: lib/pages/riderhome_page.dart (ฉบับเต็ม - อัปเดตตามระยะทาง 10 เมตร)

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
// import 'rider_history_page.dart';
// import 'parcel_detail_page.dart';

// -----------------------------
// Utilities (ควรแยกไปไฟล์ใหม่ เช่น lib/utils/location_utils.dart)
// -----------------------------
Future<bool> ensureLocationPermission() async {
  // --- ขอ Permission และเช็ค Service ---
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    log('[ensurePermission] Location service disabled.');
    // ควรแสดง SnackBar หรือ Dialog แจ้งผู้ใช้ให้เปิด GPS
    return false;
  }
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    log('[ensurePermission] Permission denied, requesting...');
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      log('[ensurePermission] Permission denied again.');
      // ควรแสดง SnackBar แจ้งว่าไม่ได้รับอนุญาต
      return false;
    }
  }
  if (permission == LocationPermission.deniedForever) {
    log('[ensurePermission] Permission denied forever.');
    // ควรแสดง Dialog แนะนำให้ไปเปิดใน Settings ของแอป
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
// Utilities (ควรแยกไปไฟล์ใหม่ เช่น lib/utils/ui_utils.dart)
// -----------------------------
Color statusColor(String status) {
  switch (status) {
    case 'created':
      return Colors.blue.shade600;
    case 'assigned':
      return Colors.orange.shade700;
    case 'picked':
      return Colors.purple.shade600;
    case 'delivered':
      return Colors.green.shade700;
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
      return Colors.green.shade50;
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

  // ใช้ didChangeDependencies เพื่อรับ Arguments จาก Route
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    log('[RiderHome] didChangeDependencies');
    // ดึง phone แค่ครั้งแรกที่ Widget ถูกสร้าง หรือ Dependencies เปลี่ยน
    if (phone == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        // เช็ค notEmpty เพิ่ม
        phone = args;
        log('[RiderHome] Received phone: $phone');
        _checkForExistingActiveJob(); // ตรวจสอบงานค้างเมื่อเปิดแอป
      } else {
        log('[RiderHome] Did not receive a valid phone number.');
        // ควรจัดการกรณีไม่ได้รับ phone เช่น แสดงข้อผิดพลาด หรือเด้งกลับไป Login
        // WidgetsBinding.instance.addPostFrameCallback((_) {
        //   if (mounted) {
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(content: Text('เกิดข้อผิดพลาด: ไม่พบข้อมูล Rider')),
        //     );
        //     // อาจจะ Navigate กลับไป Login
        //     // Navigator.of(context).pushReplacementNamed('/login');
        //   }
        // });
      }
    }
  }

  @override
  void dispose() {
    log('[RiderHome] dispose');
    _stopLocationUpdates(); // หยุด Stream และ Listener ทั้งหมดเมื่อ Widget หายไป
    super.dispose();
  }

  // ตรวจสอบว่ามีงานที่กำลังทำค้างอยู่หรือไม่เมื่อเปิดแอป
  Future<void> _checkForExistingActiveJob() async {
    log('[RiderHome] Checking for existing active job...');
    if (phone == null || phone!.isEmpty) {
      log('[RiderHome] Cannot check for job, phone is null or empty.');
      return;
    }
    try {
      final query = FirebaseFirestore.instance
          .collection('deliveries')
          .where('riderId', isEqualTo: phone) // ใช้ riderId ในการ query
          .where('status', whereIn: ['assigned', 'picked']) // สถานะที่กำลังทำ
          .limit(1); // เอาแค่งานเดียว (สมมติว่า Rider ทำได้ทีละงาน)

      final snapshot = await query.get();

      // เช็ค mounted ก่อนเรียก setState หรือ _startLocationUpdates
      if (mounted && snapshot.docs.isNotEmpty) {
        final activeDoc = snapshot.docs.first;
        log(
          '[RiderHome] Found existing active job on startup: ${activeDoc.id}',
        );
        // เริ่มอัปเดตตำแหน่งสำหรับงานที่ค้างอยู่
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

  // เริ่มกระบวนการอัปเดตตำแหน่ง (เรียกจาก _checkForExistingActiveJob หรือ NewDeliveriesPage)
  void _startLocationUpdates(String deliveryId) {
    log(
      '[RiderHome] >>> Request START location updates (distance based) for: $deliveryId',
    );
    // ป้องกันการเริ่มซ้ำซ้อนสำหรับงานเดิม
    if (_isLocationServiceRunning && _activeDeliveryId == deliveryId) {
      log('[RiderHome] Location stream already running for this delivery.');
      return;
    }

    // หยุด Stream/Listener เก่าก่อนเสมอ (เผื่อกรณีกดรับงานใหม่ซ้อน)
    _stopLocationUpdates();

    _activeDeliveryId = deliveryId; // ตั้ง ID งานปัจจุบัน
    _isLocationServiceRunning = true; // ตั้งสถานะ Service เป็นทำงาน
    _lastReportedPosition = null; // รีเซ็ตตำแหน่งล่าสุดที่ส่ง

    // 1. ขอ Permission ตำแหน่ง
    ensureLocationPermission().then((granted) {
      // เช็ค permission และสถานะ service อีกครั้ง (สำคัญ!)
      if (!granted || !_isLocationServiceRunning || !mounted) {
        log(
          '[RiderHome] Permission denied or service stopped before starting stream.',
        );
        _stopLocationUpdates(); // หยุด service ถ้าไม่ได้ permission
        if (mounted && !granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง')),
          );
        }
        return;
      }

      log('[RiderHome] Permission granted. Starting location stream...');
      // 2. เริ่มฟังสถานะของงานปัจจุบัน (เพื่อหยุดเมื่อจบงาน)
      _listenToCurrentJobStatus(deliveryId);

      // --- 3. เริ่มฟัง Location Stream ---
      _positionStreamSubscription =
          Geolocator.getPositionStream(
            // ตั้งค่า Stream
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, // ขอความแม่นยำสูง
              distanceFilter: 10, // ✅ อัปเดตทุกๆ 10 เมตร
              // สามารถเพิ่ม timeInterval ได้ถ้าต้องการจำกัดความถี่ เช่น
              // timeInterval: Duration(seconds: 5), // อย่างน้อย 5 วินาทีต่อการอัปเดต (ถ้าเคลื่อนที่เร็วมาก)
            ),
          ).listen(
            // เริ่มรับข้อมูลจาก Stream
            (Position position) {
              // Callback นี้จะทำงานเมื่อตำแหน่งเปลี่ยนไปตาม distanceFilter
              log('[RiderHome] Position stream update received.');
              if (mounted) {
                // เช็คก่อนเรียก _handlePositionUpdate
                _handlePositionUpdate(position);
              }
            },
            onError: (error) {
              log('[RiderHome] Error getting position stream: $error');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ข้อผิดพลาด Stream ตำแหน่ง: $error')),
                );
                // อาจจะลองหยุดแล้วเริ่มใหม่ หรือแจ้งให้ Rider ตรวจสอบ GPS
                _stopLocationUpdates(); // หยุดไปเลยเพื่อความปลอดภัย
              }
            },
            onDone: () {
              // Stream ถูกปิด (อาจเกิดจากระบบ หรือ permission ถูกถอน)
              log('[RiderHome] Position stream is done.');
              // ถ้า service ควรยังทำงานอยู่ (เช่น งานยังไม่จบ) อาจต้องแจ้งเตือนหรือลองเริ่มใหม่
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
            cancelOnError: true, // หยุด Stream ทันทีถ้าเกิด Error
          );
      // --- จบส่วน Location Stream ---

      log('[RiderHome] Location stream listener started for $deliveryId.');

      // 4. (Optional) ดึงตำแหน่งปัจจุบันครั้งแรกทันที (เพื่อให้มีข้อมูลเร็วขึ้น)
      _getInitialPositionAndUpdate();
    });
  }

  // (Optional) ดึงตำแหน่งปัจจุบันครั้งแรกเพื่อแสดงผลเร็วขึ้น และส่งให้ Firestore
  Future<void> _getInitialPositionAndUpdate() async {
    log('[RiderHome] Getting initial position...');
    try {
      // ขอ Permission อีกครั้ง เผื่อยังไม่ได้ให้
      bool permissionGranted = await ensureLocationPermission();
      if (!permissionGranted || !_isLocationServiceRunning || !mounted) return;

      Position initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20), // เพิ่ม timeout ป้องกันค้างนาน
      );
      log(
        '[RiderHome] Got initial position: ${initialPosition.latitude}, ${initialPosition.longitude}',
      );
      // เช็คว่า service ยังควรทำงานอยู่หรือไม่ ก่อนเรียก handle
      if (_isLocationServiceRunning && mounted) {
        _handlePositionUpdate(initialPosition, isInitial: true);
      }
    } catch (e) {
      log("[RiderHome] Error getting initial position: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถดึงตำแหน่งเริ่มต้นได้: $e')),
        );
        // ถ้าดึงตำแหน่งแรกไม่ได้ อาจจะยังให้ Stream ทำงานต่อไป หรือจะหยุดเลยก็ได้
        // _stopLocationUpdates();
      }
    }
  }

  // ฟังก์ชันจัดการเมื่อได้รับตำแหน่งใหม่จาก Stream หรือการดึงครั้งแรก
  void _handlePositionUpdate(Position position, {bool isInitial = false}) {
    // เช็คสถานะ Service และ ID งาน อีกครั้ง (สำคัญมาก!)
    if (!_isLocationServiceRunning || _activeDeliveryId == null || !mounted) {
      log(
        '[RiderHome] Received position update but conditions not met (service stopped, no active job, or not mounted).',
      );
      // ถ้า service ไม่ควรทำงาน ควรหยุด stream (อาจทำใน _stopLocationUpdates)
      return;
    }

    final currentLatLng = LatLng(position.latitude, position.longitude);
    log(
      '[RiderHome] ${isInitial ? "Initial" : "Stream"} Position Update Handled: Lat=${currentLatLng.latitude}, Lng=${currentLatLng.longitude}, Acc=${position.accuracy}m',
    );

    // ป้องกันการส่งตำแหน่งซ้ำ ถ้า Lat/Lng ไม่เปลี่ยนเลย (ป้องกัน Firestore write โดยไม่จำเป็น)
    // อาจปรับปรุงให้เช็คระยะทางน้อยๆ แทนการเช็คค่าเป๊ะๆ
    const double minDistanceThreshold =
        1.0; // ต้องห่างจากจุดเดิม > 1 เมตร ถึงจะส่ง
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

    // --- อัปเดต Firestore ---
    FirebaseFirestore.instance
        .collection('deliveries')
        .doc(_activeDeliveryId!) // ใช้ ID งานปัจจุบัน
        .update({
          'riderLocation': GeoPoint(
            currentLatLng.latitude,
            currentLatLng.longitude,
          ), // ตำแหน่ง GeoPoint
          'riderLocationTimestamp':
              FieldValue.serverTimestamp(), // เวลาที่อัปเดต (Server time)
          'riderLocationAccuracy': position.accuracy, // ความแม่นยำ (Optional)
        })
        .then((_) {
          log(
            '[RiderHome] Firestore location updated successfully for $_activeDeliveryId.',
          );
          // บันทึกตำแหน่งล่าสุดที่ส่งสำเร็จ
          _lastReportedPosition = currentLatLng;
        })
        .catchError((error) {
          // จัดการ Error ที่อาจเกิดขึ้นตอน Update Firestore
          log(
            '[RiderHome] Error updating Firestore location for $_activeDeliveryId: $error',
          );
          if (mounted) {
            // อาจจะแสดง SnackBar แต่ระวังแสดงถี่ไปถ้า Network ไม่ดี
            // ScaffoldMessenger.of(context).showSnackBar(
            //    SnackBar(content: Text('เกิดข้อผิดพลาดในการอัปเดตตำแหน่ง Firestore: $error'), duration: Duration(seconds: 2))
            // );
          }
        });
    // --- จบการอัปเดต Firestore ---
  }

  // ฟังสถานะของงานปัจจุบัน (เพื่อหยุด Stream เมื่อจบงาน)
  void _listenToCurrentJobStatus(String deliveryId) {
    _currentJobStatusSubscription?.cancel(); // ยกเลิก Listener เก่า
    log('[RiderHome] Starting to listen job status for $deliveryId');
    _currentJobStatusSubscription = FirebaseFirestore.instance
        .collection('deliveries')
        .doc(deliveryId) // ฟัง Document ของงานนี้
        .snapshots() // รับการเปลี่ยนแปลงแบบ Realtime
        .listen(
          (DocumentSnapshot snapshot) {
            // ใช้ DocumentSnapshot
            // เช็คก่อนว่า Widget ยังอยู่ และ Service ควรทำงาน
            if (!mounted || !_isLocationServiceRunning) {
              log(
                '[RiderHome] Job Status Listener: Not mounted or service stopped. Stopping updates.',
              );
              _stopLocationUpdates(); // หยุดถ้า Widget หายไป หรือ Service ถูกสั่งหยุด
              return;
            }
            if (!snapshot.exists) {
              log(
                '[RiderHome] Job Status Listener: Delivery document $deliveryId not found. Stopping updates.',
              );
              _stopLocationUpdates();
              return;
            }

            final data = snapshot.data() as Map<String, dynamic>?; // Cast data
            final status = data?['status'] as String?;
            log(
              '[RiderHome] Job Status Listener: Current job ($deliveryId) status update: $status',
            );

            // ถ้าสถานะไม่ใช่งานที่กำลังทำ ('assigned' หรือ 'picked') ให้หยุด Location Stream
            if (status != 'assigned' && status != 'picked') {
              log(
                '[RiderHome] Job Status Listener: Job status changed to $status. Stopping location updates.',
              );
              _stopLocationUpdates(); // เรียกฟังก์ชันหยุดการทำงานทั้งหมด
            }
          },
          onError: (error) {
            log(
              '[RiderHome] Job Status Listener: Error listening to current job status ($deliveryId): $error',
            );
            // หยุด Location Stream ถ้าเกิด Error ในการฟังสถานะ
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
            // หยุด Location Stream ถ้า Listener สถานะจบการทำงาน (อาจเกิดเมื่อ Document ถูกลบ)
            if (mounted && _isLocationServiceRunning) {
              _stopLocationUpdates();
            }
          },
          cancelOnError: true, // หยุด Listener ถ้ามี Error
        );
  }

  // หยุดกระบวนการอัปเดตตำแหน่งทั้งหมด (Location Stream และ Status Listener)
  void _stopLocationUpdates() {
    // เช็คว่ามีอะไรต้องหยุดบ้าง เพื่อป้องกันการเรียก cancel บน null
    bool wasRunning = _isLocationServiceRunning; // เก็บสถานะก่อนหยุด
    if (wasRunning ||
        _positionStreamSubscription != null ||
        _currentJobStatusSubscription != null) {
      log(
        '[RiderHome] >>> Stopping location updates for $_activeDeliveryId...',
      );

      // 1. หยุด Location Stream
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      log('[RiderHome] Position stream subscription canceled.');

      // 2. หยุด Listener สถานะงาน
      _currentJobStatusSubscription?.cancel();
      _currentJobStatusSubscription = null;
      log('[RiderHome] Job status subscription canceled.');

      // 3. รีเซ็ตค่า State ที่เกี่ยวข้อง
      _activeDeliveryId = null;
      _isLocationServiceRunning = false; // สำคัญ: ตั้งค่านี้เป็น false
      _lastReportedPosition = null;

      log('[RiderHome] Location updates stopped completely.');
    } else {
      log('[RiderHome] Stop location updates called, but nothing was running.');
    }
  }

  // --- ฟังก์ชัน Utilities เดิม ---
  // Future<bool> ensureLocationPermission() async { /* ... ย้ายไปข้างบนแล้ว ... */ }

  // --- ฟังก์ชันจัดการการสลับ Tab ---
  void _onItemTapped(int index) {
    // ไม่มีการ Logout ที่นี่แล้ว Logic อยู่ใน ProfilePage
    if (_selectedIndex != index) {
      // เปลี่ยน State ต่อเมื่อ index เปลี่ยนจริง
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // สร้าง Callback function ที่จะส่งให้ NewDeliveriesPage
    // ใช้ Function Type ที่ชัดเจน
    void Function(String) startUpdatesCallback = _startLocationUpdates;

    // รายการหน้าต่างๆ ที่จะแสดงใน BottomNavigationBar
    // ใช้ Widget จริง แทน Placeholder
    final pages = <Widget>[
      NewDeliveriesPage(
        phone: phone,
        onAssignSuccess: startUpdatesCallback,
      ), // หน้าแรก (รายการใหม่)
      AssignedDeliveriesPage(phone: phone), // หน้าสอง (งานของฉัน)
      RiderHistoryPage(
        phone: phone,
      ), // หน้าสาม (ประวัติ) - ต้องสร้าง Widget นี้
      ProfilePage(currentUserPhone: phone, isRider: true), // หน้าสี่ (โปรไฟล์)
    ];
    // รายการชื่อ Title สำหรับ AppBar (Optional)
    final titles = ['รายการใหม่', 'งานของฉัน', 'ประวัติ', 'โปรไฟล์'];

    log('[RiderHome] Building UI with selectedIndex: $_selectedIndex');

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_selectedIndex]), // แสดง Title ตาม Tab ที่เลือก
        automaticallyImplyLeading: false, // ไม่มีปุ่ม Back อัตโนมัติ
        centerTitle: true, // จัด Title ไว้ตรงกลาง (Optional)
      ),
      // ใช้ IndexedStack เพื่อรักษา State ของแต่ละหน้าเมื่อสลับ Tab
      body: IndexedStack(index: _selectedIndex, children: pages),
      // Bottom Navigation Bar
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
        currentIndex: _selectedIndex, // Tab ที่เลือกปัจจุบัน
        onTap: _onItemTapped, // ฟังก์ชันที่จะเรียกเมื่อกด Tab
        type: BottomNavigationBarType.fixed, // ให้ Label แสดงตลอดเวลา
        selectedItemColor: Theme.of(
          context,
        ).primaryColor, // สีไอคอน/Label ที่เลือก
        unselectedItemColor:
            Colors.grey.shade600, // สีไอคอน/Label ที่ไม่ได้เลือก
        showUnselectedLabels: true, // แสดง Label ของ Tab ที่ไม่ได้เลือกด้วย
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
  // Callback function to notify RiderhomePage when an order is assigned
  final void Function(String deliveryId)? onAssignSuccess;

  const NewDeliveriesPage({super.key, this.phone, this.onAssignSuccess});

  @override
  State<NewDeliveriesPage> createState() => _NewDeliveriesPageState();
}

class _NewDeliveriesPageState extends State<NewDeliveriesPage> {
  // Function to assign the order to the current rider
  Future<void> _assignOrder(String deliveryId) async {
    // Check if rider phone is available
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
      // Update the delivery document in Firestore
      await FirebaseFirestore.instance
          .collection('deliveries')
          .doc(deliveryId)
          .update({
            'status': 'assigned', // Update status
            'riderId': widget.phone, // Set riderId
            'assignedAt':
                FieldValue.serverTimestamp(), // Record assignment time
          });

      log('[NewDeliveries] Order $deliveryId assigned successfully.');
      // --- ✨ Call the callback function to start location updates ✨ ---
      widget.onAssignSuccess?.call(deliveryId);
      // ---------------------------------------------------------------

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รับออเดอร์เรียบร้อยแล้ว')),
        );
        // Optional: Navigate to 'AssignedDeliveriesPage' or Map page automatically
        // (Consider user experience - maybe stay on the list is better)
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
    // Query for deliveries with 'created' status (and optionally riderId == null)
    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('status', isEqualTo: 'created')
        // .where('riderId', isNull: true) // You might want this filter
        .orderBy('createdAt', descending: true); // Show newest first

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(), // Listen to real-time updates
      builder: (context, snapshot) {
        // Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          log('[NewDeliveries] Stream waiting...');
          return const Center(child: CircularProgressIndicator());
        }
        // Handle error state
        if (snapshot.hasError) {
          log('[NewDeliveries] Stream error: ${snapshot.error}');
          // Specific check for missing index error
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
        // Handle no data state
        // Use null-safe access ?.docs and default to empty list []
        final docs = snapshot.data?.docs ?? [];
        log('[NewDeliveries] Stream received data: ${docs.length} documents.');
        if (docs.isEmpty) {
          return const Center(child: Text('ยังไม่มีรายการพัสดุใหม่'));
        }

        // Build the list if data exists
        return RefreshIndicator(
          // Add pull-to-refresh
          onRefresh: () async {
            // Although StreamBuilder updates automatically, this gives user feedback
            log('[NewDeliveries] Refresh triggered.');
            // You could potentially re-run the query or just wait for the stream
            await Future.delayed(
              const Duration(milliseconds: 500),
            ); // Simulate refresh
          },
          child: ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              // --- Extract data safely ---
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
              final senderId =
                  data['senderId'] as String? ?? ''; // Phone number
              final receiverName = data['receiverName'] as String? ?? 'N/A';
              final receiverPhone = data['receiverPhone'] as String? ?? '';
              // --- End data extraction ---

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 6.0,
                ),
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sender Info Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            // Prevents overflow if name is long
                            child: Text(
                              'ผู้ส่ง: $senderName ($senderId)',
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
                              color: Theme.of(context).primaryColor,
                            ),
                            label: Text(
                              distanceString,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      Text(
                        'รับจาก: $senderAddressText',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Divider(height: 20, thickness: 0.5),
                      // Receiver Info Row
                      Text(
                        'ผู้รับ: $receiverName ($receiverPhone)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
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
                      // Action Buttons Row
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
                                side: BorderSide(color: Colors.grey.shade400),
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
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              // Call _assignOrder when pressed
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
    // Check if Rider ID is available
    if (phone == null || phone!.isEmpty) {
      return const Center(child: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้'));
    }

    // Query for deliveries assigned to this rider and in progress
    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('riderId', isEqualTo: phone)
        .where('status', whereIn: ['assigned', 'picked']) // Only active jobs
        .orderBy(
          'assignedAt',
          descending: true,
        ); // Show recently assigned first

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        // Handle loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        // Handle error state
        if (snapshot.hasError) {
          log('[AssignedDeliveries] Stream error: ${snapshot.error}');
          return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }
        // Handle no data state
        final deliveries = snapshot.data?.docs ?? [];
        if (deliveries.isEmpty) {
          return const Center(child: Text('คุณยังไม่มีงานที่กำลังดำเนินการ'));
        }

        // Build the list
        return ListView.builder(
          itemCount: deliveries.length,
          itemBuilder: (context, index) {
            final delivery = deliveries[index];
            final data = delivery.data() as Map<String, dynamic>;

            // Extract data safely
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

            // Calculate distance (optional)
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
              margin: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 6.0,
              ),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row with Status
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
                        _StatusChipSmall(
                          status: status,
                        ), // Use a smaller status chip
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Sender Info
                    Text(
                      'รับจาก: $senderName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      senderAddressText,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                    const Divider(height: 20, thickness: 0.5),
                    // Receiver Info
                    Text(
                      'ส่งให้: $receiverName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      receiverAddressText,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Action Buttons Row (Wrap for responsiveness)
                    Wrap(
                      spacing: 8.0, // Horizontal space between buttons
                      runSpacing: 8.0, // Vertical space if buttons wrap
                      alignment: WrapAlignment.spaceBetween, // Distribute space
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('รายละเอียด'),
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
                            side: BorderSide(color: Colors.grey.shade400),
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('ดูแผนที่'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.green, // Use green for map button
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 12,
                            ),
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
                        // Optional: Add Distance Chip here if needed
                        Chip(
                          avatar: Icon(
                            Icons.route_outlined,
                            size: 16,
                            color: Colors.blueGrey,
                          ),
                          label: Text(
                            distanceString,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                          backgroundColor: Colors.blueGrey.withOpacity(0.1),
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
// History (ควรสร้างไฟล์แยก lib/pages/rider_history_page.dart)
// -----------------------------
class RiderHistoryPage extends StatelessWidget {
  final String? phone; // Rider's phone (ID)
  const RiderHistoryPage({super.key, this.phone});

  @override
  Widget build(BuildContext context) {
    if (phone == null || phone!.isEmpty) {
      return const Center(child: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้'));
    }

    // Query for completed ('delivered') or 'canceled' deliveries by this rider
    final query = FirebaseFirestore.instance
        .collection('deliveries')
        .where('riderId', isEqualTo: phone)
        .where(
          'status',
          whereIn: ['delivered', 'canceled'],
        ) // Include canceled jobs
        // Order by completion/cancellation time (use 'updatedAt' as a fallback)
        .orderBy('deliveredAt', descending: true)
    // You might need a composite index for this query (riderId, status, deliveredAt)
    // Firestore will provide a link in the debug console if needed.
    ;

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
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

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(
            height: 0,
            indent: 16,
            endIndent: 16,
          ), // Add divider
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;

            // Extract data
            final code =
                data['code'] as String? ??
                doc.id.substring(0, 6); // Use short ID if no code
            final to = data['receiverAddress']?['address'] as String? ?? '-';
            final status = data['status'] as String? ?? 'unknown';
            final Timestamp? timestamp =
                data['deliveredAt']
                    as Timestamp? // Prefer deliveredAt
                    ??
                data['canceledAt']
                    as Timestamp? // Fallback to canceledAt
                    ??
                data['updatedAt'] as Timestamp?; // Final fallback
            final DateTime? completedDate = timestamp?.toDate();

            String formatTimestamp(DateTime? dt) {
              if (dt == null) return '-';
              final d = dt.toLocal();
              return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
            }

            return ListTile(
              leading: Icon(
                status == 'delivered'
                    ? Icons.check_circle_outline
                    : Icons.cancel_outlined, // Icon based on status
                color: status == 'delivered' ? Colors.green : Colors.red,
              ),
              title: Text('ID: $code'),
              subtitle: Text(
                'ส่งที่: $to\nเมื่อ: ${formatTimestamp(completedDate)}',
              ),
              trailing: _StatusChipSmall(status: status), // Show status chip
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
} // End RiderHistoryPage

// -----------------------------
// Parcel Detail Page (ควรสร้างไฟล์แยก lib/pages/parcel_detail_page.dart ถ้ายังไม่ได้ทำ)
// -----------------------------
class ParcelDetailPage extends StatelessWidget {
  final String deliveryId;
  final Map<String, dynamic> data;
  const ParcelDetailPage({
    super.key,
    required this.deliveryId,
    required this.data,
  });

  // Helper widget for displaying rows
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
        Icon(icon, color: Theme.of(context).primaryColor, size: 20),
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

  // Helper to format Timestamp
  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate().toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return ts?.toString() ?? '-';
  }

  @override
  Widget build(BuildContext context) {
    // Extract address maps safely
    final senderAddr = data['senderAddress'] as Map<String, dynamic>? ?? {};
    final receiverAddr = data['receiverAddress'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? []; // Get items list

    return Scaffold(
      appBar: AppBar(
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
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Section: Sender Info
          Card(
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
                                    imageUrl,
                                    height: 150,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
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
                            const Divider(height: 16),
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
          // Optional: Display proof images if available
          if (data['pickupProofImageUrl'] != null) ...[
            const Text(
              'หลักฐานการรับของ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Image.network(data['pickupProofImageUrl']),
            ),
          ],
          if (data['deliveryProofImageUrl'] != null) ...[
            const Text(
              'หลักฐานการส่งของ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Image.network(data['deliveryProofImageUrl']),
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
      /* Same as _StatusChip */
      switch (status) {
        case 'created':
          return 'สร้างแล้ว';
        case 'assigned':
          return 'มอบหมายแล้ว';
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
          color: statusColor(status),
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: statusBackgroundColor(status),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none, // Remove border
    );
  }
}

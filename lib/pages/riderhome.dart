import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:developer';
import 'ridermap.dart'; // Import หน้าแผนที่
import 'package:latlong2/latlong.dart';

class RiderhomePage extends StatefulWidget {
  const RiderhomePage({super.key});

  @override
  State<RiderhomePage> createState() => _RiderhomePageState();
}

class _RiderhomePageState extends State<RiderhomePage> {
  int _selectedIndex = 0;
  String? phone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String) {
      phone = args;
      log('Riderhome received phone: $phone');
    }
  }

  void _onItemTapped(int index) {
    if (index == 3) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      NewDeliveriesPage(phone: phone),
      AssignedDeliveriesPage(phone: phone),
      const Center(child: Text('History Page')),
      const Center(child: Text('Logout Page')),
    ];

    final titles = ['รายการใหม่', 'งานของฉัน', 'ประวัติ', 'ออกจากระบบ'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_selectedIndex]),
        automaticallyImplyLeading: false,
      ),
      body: pages.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'รายการใหม่'),
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment_turned_in), label: 'งานของฉัน'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'ประวัติ'),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'ออกจากระบบ'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

// ฟังก์ชันคำนวณระยะทาง
String _calculateDistance(LatLng? start, LatLng? end) {
  if (start == null || end == null) {
    return 'N/A';
  }
  final double distanceInMeters = const Distance().as(LengthUnit.Meter, start, end);
  final double distanceInKm = distanceInMeters / 1000;
  return '${distanceInKm.toStringAsFixed(1)} km';
}

class NewDeliveriesPage extends StatefulWidget {
  final String? phone;
  const NewDeliveriesPage({super.key, this.phone});

  @override
  State<NewDeliveriesPage> createState() => _NewDeliveriesPageState();
}

class _NewDeliveriesPageState extends State<NewDeliveriesPage> {

  Future<void> _assignOrder(String deliveryId, BuildContext context) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รับออเดอร์เรียบร้อยแล้ว')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // --- ✨ แก้ไข Query ตรงนี้ ✨ ---
      // Query หางานที่ riderId คือเรา และ status เป็น 'assigned' หรือ 'picked'
      stream: FirebaseFirestore.instance
          .collection('deliveries')
          .where('riderId', isEqualTo: widget.phone)
          .where('status', whereIn: ['assigned', 'picked']) // <-- ใช้ whereIn
          .limit(1)
          .snapshots(),
      builder: (context, activeJobSnapshot) {
        if (activeJobSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final bool isRiderBusy = activeJobSnapshot.hasData && activeJobSnapshot.data!.docs.isNotEmpty;

        if (isRiderBusy) {
          return Center(
            child: Card(
              margin: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 40),
                    const SizedBox(height: 16),
                    const Text(
                      'คุณมีงานที่ต้องทำอยู่',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'กรุณาทำงานที่รับไว้ให้เสร็จสิ้นก่อนรับงานใหม่',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('deliveries')
              .where('status', isEqualTo: 'created')
              .snapshots(),
          builder: (context, snapshot) {
             if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(child: Text('ยังไม่มีรายการพัสดุใหม่'));
            }

            final deliveries = snapshot.data!.docs;

            return ListView.builder(
              itemCount: deliveries.length,
              itemBuilder: (context, index) {
                final delivery = deliveries[index];
                final data = delivery.data() as Map<String, dynamic>;
                
                final senderAddress = data['senderAddress'] as Map<String, dynamic>? ?? {};
                final receiverAddress = data['receiverAddress'] as Map<String, dynamic>? ?? {};
                
                final senderLat = senderAddress['lat'] as double?;
                final senderLng = senderAddress['lng'] as double?;
                final receiverLat = receiverAddress['lat'] as double?;
                final receiverLng = receiverAddress['lng'] as double?;

                final senderLatLng = (senderLat != null && senderLng != null) ? LatLng(senderLat, senderLng) : null;
                final receiverLatLng = (receiverLat != null && receiverLng != null) ? LatLng(receiverLat, receiverLng) : null;
                
                final distanceString = _calculateDistance(senderLatLng, receiverLatLng);

                final senderAddressText = senderAddress['address'] as String? ?? 'ไม่มีข้อมูลที่อยู่';
                final receiverAddressText = receiverAddress['address'] as String? ?? 'ไม่มีข้อมูลที่อยู่';

                return Card(
                  margin: const EdgeInsets.all(10.0),
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                             Text('ผู้ส่ง: ${data['senderName'] ?? 'ไม่มีชื่อ'} (${data['senderId'] ?? ''})'),
                             Chip(
                               avatar: Icon(Icons.social_distance, size: 18, color: Theme.of(context).primaryColor),
                               label: Text(distanceString),
                               backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                             )
                          ],
                        ),
                        Text('รับจาก: $senderAddressText', style: const TextStyle(color: Colors.grey)),
                        const Divider(height: 20),
                        Text('ผู้รับ: ${data['receiverName'] ?? 'ไม่มีชื่อ'} (${data['receiverPhone'] ?? ''})'),
                        Text('ส่งที่: $receiverAddressText', style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _assignOrder(delivery.id, context),
                            child: const Text('รับงาน'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class AssignedDeliveriesPage extends StatelessWidget {
  final String? phone;
  const AssignedDeliveriesPage({super.key, this.phone});

  @override
  Widget build(BuildContext context) {
    if (phone == null || phone!.isEmpty) {
      return const Center(child: Text('ไม่สามารถระบุตัวตนไรเดอร์ได้'));
    }

    return StreamBuilder<QuerySnapshot>(
      // --- ✨ แก้ไข Query ตรงนี้ ✨ ---
      // Query หางานที่ riderId คือเรา และ status เป็น 'assigned' หรือ 'picked'
      stream: FirebaseFirestore.instance
          .collection('deliveries')
          .where('riderId', isEqualTo: phone)
          .where('status', whereIn: ['assigned', 'picked']) // <-- ใช้ whereIn
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

            final senderAddress = data['senderAddress'] as Map<String, dynamic>? ?? {};
            final receiverAddress = data['receiverAddress'] as Map<String, dynamic>? ?? {};

            final senderLat = senderAddress['lat'] as double?;
            final senderLng = senderAddress['lng'] as double?;
            final receiverLat = receiverAddress['lat'] as double?;
            final receiverLng = receiverAddress['lng'] as double?;

            final senderLatLng = (senderLat != null && senderLng != null) ? LatLng(senderLat, senderLng) : null;
            final receiverLatLng = (receiverLat != null && receiverLng != null) ? LatLng(receiverLat, receiverLng) : null;
            
            final distanceString = _calculateDistance(senderLatLng, receiverLatLng);

            final senderAddressText = senderAddress['address'] as String? ?? 'ไม่มีข้อมูลที่อยู่';
            final receiverAddressText = receiverAddress['address'] as String? ?? 'ไม่มีข้อมูลที่อยู่';

            return Card(
              margin: const EdgeInsets.all(10.0),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                           avatar: Icon(Icons.social_distance, size: 18, color: Colors.green),
                           label: Text(distanceString),
                           backgroundColor: Colors.green.withOpacity(0.1),
                         )
                      ],
                    ),
                    Text('จาก: $senderAddressText', style: const TextStyle(color: Colors.grey)),
                    const Divider(height: 20),
                    Text('ผู้รับ: ${data['receiverName'] ?? 'ไม่มีชื่อ'}'),
                    Text('ไป: $receiverAddressText', style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
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
                              builder: (context) => RiderMapPage(
                                deliveryData: data,
                                deliveryId: delivery.id,
                              ),
                            ),
                          );
                        },
                      ),
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
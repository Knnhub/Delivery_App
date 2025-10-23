import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliver_app/firebase_options.dart';
import 'package:deliver_app/pages/firebase.dart';
import 'package:deliver_app/pages/list.dart';
import 'package:deliver_app/pages/profile.dart';
import 'package:deliver_app/pages/receive.dart';
import 'package:deliver_app/pages/riderhome.dart';
import 'package:deliver_app/pages/sendpage.dart';
import 'package:deliver_app/pages/tracking_map_page.dart';
import 'package:deliver_app/pages/userhome.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'pages/home.dart';
import 'pages/login.dart';
import 'pages/register.dart';
import 'pages/rider_detail_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Connnect to FireStore
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delivery App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/signup': (context) => const RegisterPage(),
        '/firebase': (context) => const FirebasePage(),
        '/userHome': (ctx) => const UserhomePage(), // หลัง Login เป็น user
        '/riderHome': (ctx) => const RiderhomePage(), // หลัง Login เป็น rider
        '/profile': (ctx) => const ProfilePage(), // หน้าโปรไฟล์
        '/list': (ctx) => const listPage(), // หน้าแสดงรายการพัสดุของผู้ใช้
        '/send': (ctx) => const SendPage(), // หน้าเพิ่มพัสดุ
        '/ride': (ctx) => const RiderhomePage(), // หน้า rider
        '/receive': (ctx) => const ReceivePage(), // หน้า รับพัสดุ
        '/trackingMap': (ctx) =>
            const TrackingMapPage(receiverPhone: 'demoPhone'),
        '/riderDetail': (ctx) => RiderDetailPage(
          riderId: ModalRoute.of(ctx)!.settings.arguments as String,
        ), // หน้าแสดงรายละเอียด Rider
      },
    );
  }
}

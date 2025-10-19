// user_home_page.dart
import 'dart:developer';
import 'package:deliver_app/pages/profile.dart';
import 'package:deliver_app/pages/list.dart';
import 'package:deliver_app/pages/receive.dart';
import 'package:flutter/material.dart';
import 'package:deliver_app/pages/sendpage.dart';

class UserhomePage extends StatefulWidget {
  const UserhomePage({super.key, this.senderPhone});
  final String? senderPhone; // เบอร์ผู้ส่ง (ไว้ส่งต่อให้ listPage)

  @override
  State<UserhomePage> createState() => _UserhomeState();
}

class _UserhomeState extends State<UserhomePage> {
  int _currentIndex = 0;
  final _navKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());
  String? senderPhone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ฟังก์ชันนี้จะถูกเรียกเพื่อให้เราดึงค่า arguments ที่ถูกส่งมาได้
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String) {
      senderPhone = args;
      log('Userhome received phone: $senderPhone');
    }
  }
  // --- จบส่วนที่เพิ่มเข้ามา ---

  Future<bool> _onWillPop() async {
    final nav = _navKeys[_currentIndex].currentState!;
    if (nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  Widget _buildTabNavigator({required int index, required Widget root}) {
    return Navigator(
      key: _navKeys[index],
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => root, settings: settings),
    );
  }

  void _onTap(int i) {
    if (i == 3) {
      // Navigator.of(context, rootNavigator: true).pushReplacementNamed('/login');
      // return;
    }
    if (_currentIndex == i) {
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _currentIndex = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            // ✅ ใช้ listPage เป็นหน้าในแท็บ List
            _buildTabNavigator(
              index: 0,
              root: listPage(senderPhone: senderPhone),
            ),
            _buildTabNavigator(
              index: 1,
              root: SendPage(senderPhone: senderPhone),
            ),
            _buildTabNavigator(
              index: 2,
              root: ReceivePage(currentUserPhone: senderPhone),
            ),
            _buildTabNavigator(
              index: 3,
              root: ProfilePage(currentUserPhone: senderPhone),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: _onTap,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'List'),
            BottomNavigationBarItem(icon: Icon(Icons.send), label: 'Send'),
            BottomNavigationBarItem(
              icon: Icon(Icons.move_to_inbox),
              label: 'Receive',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'profile'),
          ],
        ),
      ),
    );
  }
}

class _ReceiveRootPage extends StatelessWidget {
  const _ReceiveRootPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Receive')),
      body: Center(child: Text('Receive Root')),
    );
  }
}

class _LogoutPlaceholder extends StatelessWidget {
  const _LogoutPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

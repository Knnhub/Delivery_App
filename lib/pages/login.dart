import 'dart:convert';
import 'dart:developer';
import 'package:crypto/crypto.dart' show sha256;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final phoneCtl = TextEditingController();
  final passwordCtl = TextEditingController();
  String role = 'user'; // 'user' | 'rider'

  final db = FirebaseFirestore.instance;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เข้าสู่ระบบ')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: phoneCtl,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: passwordCtl,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: role,
              items: const [
                DropdownMenuItem(value: 'user', child: Text('User')),
                DropdownMenuItem(value: 'rider', child: Text('Rider')),
              ],
              onChanged: (v) => setState(() => role = v ?? 'user'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : login,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }

  String hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> login() async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = phoneCtl.text.trim();
    final pass = passwordCtl.text;

    if (phone.isEmpty || pass.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('กรอกข้อมูลให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final doc = await db.collection(role).doc(phone).get();
      if (!doc.exists) {
        messenger.showSnackBar(const SnackBar(content: Text('ไม่พบบัญชีนี้')));
        return;
      }
      final data = doc.data() as Map<String, dynamic>;
      final storedHash = (data['passwordHash'] ?? '') as String;
      final inputHash = hashPassword(pass);

      if (storedHash == inputHash) {
        log('Login success as $role: $phone');
        messenger.showSnackBar(
          const SnackBar(content: Text('เข้าสู่ระบบสำเร็จ')),
        );
        if (!mounted) return;
        // เปลี่ยนเส้นทางตามบทบาท (คุณสามารถแก้เป็นหน้าเป้าหมายจริงภายหลังได้)
        final nextRoute = role == 'user' ? '/userHome' : '/riderHome';
        Navigator.pushReplacementNamed(context, nextRoute);
      } else {
        messenger.showSnackBar(
          const SnackBar(content: Text('รหัสผ่านไม่ถูกต้อง')),
        );
      }
    } on FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Firebase error: ${e.message ?? e.code}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

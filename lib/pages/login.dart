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
  final nameCtl = TextEditingController();
  final passwordCtl = TextEditingController();
  final db = FirebaseFirestore.instance;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    nameCtl.dispose();
    passwordCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E0FA),
      body: SafeArea(
        child: Stack(
          children: [
            // Back button ฟิกมุมซ้ายบน
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),

            LayoutBuilder(
              builder: (context, constraints) {
                final isTall = constraints.maxHeight > 720;

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: isTall ? 24 : 12),

                          // Logo / ภาพประกอบ (ขนาดยืดหยุ่น)
                          // AspectRatio(
                          //   aspectRatio: 1,
                          //   child: Container(
                          //     decoration: BoxDecoration(
                          //       color: Colors.white,
                          //       borderRadius: BorderRadius.circular(12),
                          //     ),
                          //     // child: ... (ใส่โลโก้/ภาพได้ตามต้องการ)
                          //   ),
                          // ),
                          SizedBox(height: isTall ? 40 : 24),

                          // Username
                          TextField(
                            controller: nameCtl,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            decoration: InputDecoration(
                              hintText: 'เบอร์โทรศัพท์',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Password
                          TextField(
                            controller: passwordCtl,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _loading ? null : login(),
                            decoration: InputDecoration(
                              hintText: 'รหัสผ่าน',
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 18,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: BorderSide.none,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                color: Colors.black.withOpacity(0.6),
                              ),
                            ),
                          ),

                          SizedBox(height: isTall ? 32 : 20),

                          // Login button
                          SizedBox(
                            height: 57,
                            child: ElevatedButton(
                              onPressed: _loading ? null : login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8C78E8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                elevation: 0,
                                foregroundColor: const Color(0xFFE9D5FF),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Color(0xFFE9D5FF),
                                            ),
                                      ),
                                    )
                                  : const Text(
                                      'เข้าสู่ระบบ',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),

                          SizedBox(height: isTall ? 16 : 8),
                        ],
                      ),
                    ),
                  ),
                );
              },
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
    final name = nameCtl.text.trim();
    final pass = passwordCtl.text;

    if (name.isEmpty || pass.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('กรอกข้อมูลให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      DocumentSnapshot<Map<String, dynamic>>? doc;
      String? detectedRole;

      final userQuery = await db
          .collection('user')
          .where('phone', isEqualTo: name)
          .limit(1)
          .get();
      if (userQuery.docs.isNotEmpty) {
        doc = userQuery.docs.first;
        detectedRole = 'user';
      } else {
        final riderQuery = await db
            .collection('rider')
            .where('phone', isEqualTo: name)
            .limit(1)
            .get();
        if (riderQuery.docs.isNotEmpty) {
          doc = riderQuery.docs.first;
          detectedRole = 'rider';
        }
      }

      if (doc == null || !doc.exists) {
        messenger.showSnackBar(const SnackBar(content: Text('ไม่พบบัญชีนี้')));
        return;
      }

      final data = doc.data()!;
      final storedHash = (data['passwordHash'] ?? '') as String;
      final inputHash = hashPassword(pass);

      if (storedHash == inputHash) {
        final roleFromDoc = (data['role'] as String?)?.toLowerCase();
        final role = (roleFromDoc == 'rider' || detectedRole == 'rider')
            ? 'rider'
            : 'user';

        log('Login success as $role: $name');
        messenger.showSnackBar(
          const SnackBar(content: Text('เข้าสู่ระบบสำเร็จ')),
        );
        if (!mounted) return;
        final nextRoute = role == 'user' ? '/userHome' : '/riderHome';
        Navigator.pushReplacementNamed(context, nextRoute, arguments: name);
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

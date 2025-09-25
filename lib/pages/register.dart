import 'dart:convert';
import 'dart:developer';
import 'package:crypto/crypto.dart' show sha256;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  @override
  var phoneCtl = TextEditingController();
  var passwordCtl = TextEditingController();
  var nameCtl = TextEditingController();
  // var role = TextEditingController();
  String role = 'user';
  var db = FirebaseFirestore.instance; // ตัวเชื่อมไป Firestore

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: phoneCtl,
              decoration: InputDecoration(labelText: 'Phone Number'),
            ),
            TextField(
              controller: passwordCtl,
              decoration: InputDecoration(labelText: 'Password'),
            ),
            TextField(
              controller: nameCtl,
              decoration: InputDecoration(labelText: 'name'),
            ),
            DropdownButton<String>(
              value: role,
              items: const [
                DropdownMenuItem(value: 'user', child: Text('User')),
                DropdownMenuItem(value: 'rider', child: Text('Rider')),
              ],
              onChanged: (value) {
                setState(() {
                  role = value ?? 'user';
                });
              },
            ),
            Row(
              children: [
                FilledButton(onPressed: register, child: Text('Register')),
              ],
            ),
            // Row(
            //   children: [
            //     FilledButton(onPressed: readData, child: Text('readData')),
            //   ],
            // ),
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

  void register() async {
    // TODO: Firestore action

    var data = {
      'phone': phoneCtl.text,
      'passwordHash': hashPassword(passwordCtl.text),
      'name': nameCtl.text,
      'role': role,
      'createdAt': DateTime.timestamp(),
    };
    await db.collection(role).doc(phoneCtl.text).set(data);
    log("Registered in collection $role with phone ${phoneCtl.text}");
    // db.collection('inbox').doc(docCtl.text).set(data);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  void readData() async {
    DocumentSnapshot result = await db
        .collection(role)
        .doc(phoneCtl.text)
        .get();
    var data = result.data();
    log(data.toString());
  }
}

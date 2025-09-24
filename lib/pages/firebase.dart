import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FirebasePage extends StatefulWidget {
  const FirebasePage({super.key});

  @override
  State<FirebasePage> createState() => _FirebasePageState();
}

class _FirebasePageState extends State<FirebasePage> {
  var docCtl = TextEditingController();
  var nameCtl = TextEditingController();
  var messageCtl = TextEditingController();
  var db = FirebaseFirestore.instance; // ตัวเชื่อมไป Firestore
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: docCtl,
              decoration: InputDecoration(labelText: 'Document'),
            ),
            TextField(
              controller: nameCtl,
              decoration: InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: messageCtl,
              decoration: InputDecoration(labelText: 'Message'),
            ),
            Row(
              children: [
                FilledButton(onPressed: addData, child: Text('Add Data')),
                FilledButton(onPressed: readData, child: Text('Read Data')),
                FilledButton(onPressed: queryData, child: Text('Query Data')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void addData() {
    // TODO: Firestore action

    var data = {
      'name': nameCtl.text,
      'message': messageCtl.text,
      'createAt': DateTime.timestamp(),
    };
    db.collection('inbox').doc(docCtl.text).set(data);
  }

  void readData() async {
    DocumentSnapshot result = await db
        .collection('inbox')
        .doc(docCtl.text)
        .get();
    var data = result.data();
    log(data.toString());
  }

  void queryData() async {
    var indexRef = db.collection('inbox');
    var query = indexRef.where("name", isEqualTo: nameCtl.text);
    var result = await query.get();
    if (result.docs.isNotEmpty) {
      log(result.docs.first.data()['message']);
    } else {
      log('No data');
    }
  }
}

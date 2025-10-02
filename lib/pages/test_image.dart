import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';

class TestImage extends StatefulWidget {
  const TestImage({super.key});

  @override
  State<TestImage> createState() => _TestImageState();
}

class _TestImageState extends State<TestImage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _imageFile;
  String? _uploadedUrl;
  bool _uploading = false;

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked != null) {
      setState(() {
        _imageFile = picked;
      });
      await _uploadToFirebase(File(picked.path));
    }
  }

  Future<void> _uploadToFirebase(File file) async {
    setState(() => _uploading = true);

    try {
      // ตั้ง path ใน storage
      final ref = FirebaseStorage.instance
          .ref()
          .child('test_images')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = await ref.putFile(file);
      final url = await uploadTask.ref.getDownloadURL();

      setState(() {
        _uploadedUrl = url;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Upload success!')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Test Image Upload")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_imageFile != null)
              Image.file(File(_imageFile!.path), height: 150),
            if (_uploadedUrl != null) ...[
              const SizedBox(height: 16),
              Text("Uploaded URL:"),
              SelectableText(_uploadedUrl!),
              Image.network(_uploadedUrl!, height: 150),
            ],
            const SizedBox(height: 20),
            if (_uploading) const CircularProgressIndicator(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo),
                  label: const Text("Gallery"),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Camera"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

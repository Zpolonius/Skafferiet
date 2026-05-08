import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

class ImageUploadService {
  static final _picker = ImagePicker();

  /// Shows a source picker sheet, then uploads the image to [storagePath] in
  /// Firebase Storage. Returns the download URL, or null if the user cancelled.
  static Future<String?> pickAndUpload(
    BuildContext context, {
    required String storagePath,
  }) async {
    final source = await _showSourceSheet(context);
    if (source == null) return null;

    final file = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1080,
    );
    if (file == null) return null;

    final ref = FirebaseStorage.instance
        .ref('$storagePath/${const Uuid().v4()}.jpg');
    await ref.putFile(File(file.path));
    return ref.getDownloadURL();
  }

  static Future<ImageSource?> _showSourceSheet(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tag et billede'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Vælg fra bibliotek'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

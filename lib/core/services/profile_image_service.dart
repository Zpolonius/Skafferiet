import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Available actions when configuring user profile image.
enum ProfileImageAction {
  camera,
  gallery,
  delete,
}

/// Abstract contract for profile image picking, uploading, and deleting (ISP & DIP).
abstract class ProfileImageService {
  /// Prompts the user to pick an image or delete their current image,
  /// then uploads to Storage if chosen.
  ///
  /// Returns:
  /// - The download URL string if an image was uploaded.
  /// - An empty string `''` if the user chose to delete their image.
  /// - `null` if the action was cancelled or failed due to permission denial.
  Future<String?> pickAndUploadProfileImage(
    BuildContext context, {
    required String userId,
    bool showDeleteOption = false,
  });

  /// Deletes the avatar file from Firebase Storage.
  Future<void> deleteProfileImage({required String userId});
}

/// Production implementation of [ProfileImageService] using [ImagePicker] and [FirebaseStorage].
class FirebaseProfileImageService implements ProfileImageService {
  final ImagePicker _picker;
  final FirebaseStorage _storage;

  FirebaseProfileImageService({
    ImagePicker? picker,
    FirebaseStorage? storage,
  })  : _picker = picker ?? ImagePicker(),
        _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<String?> pickAndUploadProfileImage(
    BuildContext context, {
    required String userId,
    bool showDeleteOption = false,
  }) async {
    final action = await showSourceSheet(context, showDeleteOption: showDeleteOption);
    if (action == null) return null;

    if (action == ProfileImageAction.delete) {
      await deleteProfileImage(userId: userId);
      return '';
    }

    final source = action == ProfileImageAction.camera
        ? ImageSource.camera
        : ImageSource.gallery;

    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (file == null) return null;

      final ref = _storage.ref('users/$userId/avatar.jpg');
      await ref.putFile(File(file.path));
      return await ref.getDownloadURL();
    } on PlatformException catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tilladelse til kamera eller fotobibliotek blev afvist. Giv tilladelse i telefonens indstillinger.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Der opstod en fejl under upload af billedet.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }
  }

  @override
  Future<void> deleteProfileImage({required String userId}) async {
    try {
      final ref = _storage.ref('users/$userId/avatar.jpg');
      await ref.delete();
    } catch (_) {
      // Ignorer fejl hvis filen allerede er slettet eller ikke findes
    }
  }

  /// Displays the source sheet modal (Camera, Gallery, and optional Delete).
  static Future<ProfileImageAction?> showSourceSheet(
    BuildContext context, {
    bool showDeleteOption = false,
  }) {
    return showModalBottomSheet<ProfileImageAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Tag et billede'),
                onTap: () => Navigator.pop(ctx, ProfileImageAction.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Vælg fra bibliotek'),
                onTap: () => Navigator.pop(ctx, ProfileImageAction.gallery),
              ),
              if (showDeleteOption)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Fjern profilbillede',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () => Navigator.pop(ctx, ProfileImageAction.delete),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

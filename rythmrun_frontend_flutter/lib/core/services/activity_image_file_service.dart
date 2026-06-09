import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ActivityImageFileException implements Exception {
  final String message;

  const ActivityImageFileException(this.message);

  @override
  String toString() => message;
}

class PreparedActivityImage {
  final String clientImageId;
  final String localPath;
  final String thumbnailPath;
  final String contentType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final String? checksumSha256;

  const PreparedActivityImage({
    required this.clientImageId,
    required this.localPath,
    required this.thumbnailPath,
    required this.contentType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.checksumSha256,
  });
}

class ActivityImageFileService {
  static const int _maxUploadEdge = 1600;
  static const int _maxThumbnailEdge = 300;
  static const int _jpegQuality = 82;
  static const String _outputContentType = 'image/jpeg';
  static const Set<String> _supportedInputMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  Future<PreparedActivityImage> prepareImage({
    required int userId,
    required int localWorkoutId,
    required XFile pickedFile,
  }) async {
    final sourceFile = File(pickedFile.path);
    if (!await sourceFile.exists()) {
      throw const ActivityImageFileException('Selected image file not found');
    }

    final sourceBytes = await sourceFile.readAsBytes();
    if (sourceBytes.isEmpty) {
      throw const ActivityImageFileException('Selected image file is empty');
    }

    final inputMimeType = _resolveMimeType(pickedFile, sourceBytes);
    _validateInputMimeType(inputMimeType);

    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const ActivityImageFileException(
        'Selected image could not be decoded',
      );
    }

    final clientImageId = _generateClientImageId(
      userId: userId,
      localWorkoutId: localWorkoutId,
    );
    final uploadImage = _resizeToLongestEdge(decoded, _maxUploadEdge);
    final uploadBytes = img.encodeJpg(uploadImage, quality: _jpegQuality);
    final thumbnailImage = _resizeToLongestEdge(decoded, _maxThumbnailEdge);
    final thumbnailBytes = img.encodeJpg(thumbnailImage, quality: _jpegQuality);

    final imageDirectories = await _ensureImageDirectories(
      userId: userId,
      localWorkoutId: localWorkoutId,
    );
    final localPath = p.join(
      imageDirectories.originals.path,
      '$clientImageId.jpg',
    );
    final thumbnailPath = p.join(
      imageDirectories.thumbnails.path,
      '$clientImageId.jpg',
    );

    await File(localPath).writeAsBytes(uploadBytes, flush: true);
    await File(thumbnailPath).writeAsBytes(thumbnailBytes, flush: true);

    return PreparedActivityImage(
      clientImageId: clientImageId,
      localPath: localPath,
      thumbnailPath: thumbnailPath,
      contentType: _outputContentType,
      sizeBytes: uploadBytes.length,
      width: uploadImage.width,
      height: uploadImage.height,
      checksumSha256: sha256.convert(uploadBytes).toString(),
    );
  }

  Future<bool> exists(String path) {
    return File(path).exists();
  }

  Future<List<int>> readBytes(String path) {
    return File(path).readAsBytes();
  }

  Future<void> deleteIfExists(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return;
    }

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _resolveMimeType(XFile pickedFile, List<int> sourceBytes) {
    final mimeType =
        pickedFile.mimeType ??
        lookupMimeType(
          pickedFile.path,
          headerBytes:
              sourceBytes.length >= defaultMagicNumbersMaxLength
                  ? sourceBytes.sublist(0, defaultMagicNumbersMaxLength)
                  : sourceBytes,
        );

    if (mimeType == null || mimeType.trim().isEmpty) {
      throw const ActivityImageFileException(
        'Unable to determine selected image type',
      );
    }

    return mimeType.split(';').first.trim().toLowerCase();
  }

  void _validateInputMimeType(String mimeType) {
    if (mimeType == 'image/heic' || mimeType == 'image/heif') {
      throw const ActivityImageFileException(
        'HEIC images are not supported yet. Please choose a JPEG, PNG, or WebP image.',
      );
    }

    if (!_supportedInputMimeTypes.contains(mimeType)) {
      throw ActivityImageFileException(
        'Unsupported image type: $mimeType. Please choose a JPEG, PNG, or WebP image.',
      );
    }
  }

  img.Image _resizeToLongestEdge(img.Image source, int maxEdge) {
    final longestEdge = max(source.width, source.height);
    if (longestEdge <= maxEdge) {
      return source;
    }

    final scale = maxEdge / longestEdge;
    return img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  Future<_ActivityImageDirectories> _ensureImageDirectories({
    required int userId,
    required int localWorkoutId,
  }) async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final basePath = p.join(
      appDirectory.path,
      'activity_images',
      '$userId',
      '$localWorkoutId',
    );

    final originals = Directory(p.join(basePath, 'originals'));
    final thumbnails = Directory(p.join(basePath, 'thumbnails'));
    await originals.create(recursive: true);
    await thumbnails.create(recursive: true);

    return _ActivityImageDirectories(
      originals: originals,
      thumbnails: thumbnails,
    );
  }

  String _generateClientImageId({
    required int userId,
    required int localWorkoutId,
  }) {
    final timestampMicros = DateTime.now().microsecondsSinceEpoch;
    final random = Random.secure();
    final suffix =
        List.generate(
          8,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();

    return 'img_${userId}_${localWorkoutId}_${timestampMicros}_$suffix';
  }
}

class _ActivityImageDirectories {
  final Directory originals;
  final Directory thumbnails;

  const _ActivityImageDirectories({
    required this.originals,
    required this.thumbnails,
  });
}

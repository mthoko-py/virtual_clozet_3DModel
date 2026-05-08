// services.dart
// Virtual Clozet — Unified API service (CatVTON + SAM-3D)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// ──────────────────────────────────────────────────────────────
// 🔧 UPDATE THIS with your ngrok URL from the Colab notebook
// ──────────────────────────────────────────────────────────────
const String _baseUrl = 'https://scrambled-never-appendix.ngrok-free.dev';

class TryOnResult {
  final Uint8List tryon2dBytes;   // PNG preview image
  final Uint8List glbBytes;       // 3D GLB model
  final String message;

  const TryOnResult({
    required this.tryon2dBytes,
    required this.glbBytes,
    required this.message,
  });
}

class VirtualClozetService {
  // Health check
  Future<Map<String, dynamic>?> healthCheck() async {
    try {
      final resp = await http
          .get(Uri.parse('$_baseUrl/'),
              headers: {'ngrok-skip-browser-warning': 'true'})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return jsonDecode(resp.body);
    } catch (_) {}
    return null;
  }

  // Full pipeline: person + garment → GLB + 2D preview
  Future<TryOnResult?> tryOn3D({
    required File personPhoto,
    required File garmentImage,
    required String clothType,
    int numSteps = 10,
    double guidanceScale = 2.5,
    int seed = 42,
    void Function(String)? onProgress,
  }) async {
    try {
      onProgress?.call('Uploading images...');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/try_on_3d'),
      )..headers['ngrok-skip-browser-warning'] = 'true';

      request.files.add(await http.MultipartFile.fromPath(
          'person_image', personPhoto.path));
      request.files.add(await http.MultipartFile.fromPath(
          'garment_image', garmentImage.path));
      request.fields['category']       = _toFashnCategory(clothType);
      request.fields['num_steps']       = numSteps.toString();
      request.fields['guidance_scale']  = guidanceScale.toString();
      request.fields['seed']            = seed.toString();

      onProgress?.call('Running pipeline... (~5 min, please wait)');

      final streamed = await request.send()
          .timeout(const Duration(minutes: 15));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(minutes: 15));

      if (response.statusCode != 200) {
        onProgress?.call('Server error: ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'success') {
        onProgress?.call('Error: ${data['error']}');
        return null;
      }

      final tryon2d = base64Decode(data['tryon_2d_base64'] as String);

      onProgress?.call('Downloading 3D model...');
      final glbResp = await http
          .get(Uri.parse(data['glb_url'] as String),
              headers: {'ngrok-skip-browser-warning': 'true'})
          .timeout(const Duration(minutes: 3));

      if (glbResp.statusCode != 200) {
        onProgress?.call('GLB download failed: ${glbResp.statusCode}');
        return null;
      }

      onProgress?.call('Done! ${data['message']}');

      return TryOnResult(
        tryon2dBytes: tryon2d,
        glbBytes:     glbResp.bodyBytes,
        message:      data['message'] as String,
      );
    } catch (e) {
      onProgress?.call('Error: $e');
      return null;
    }
  }

  // Save GLB to a temp file so model_viewer_plus can load it
  Future<File> saveGlbToTemp(Uint8List glbBytes) async {
    final dir  = Directory.systemTemp;
    final file = File('${dir.path}/tryon_model_${DateTime.now().millisecondsSinceEpoch}.glb');
    await file.writeAsBytes(glbBytes);
    return file;
  }

  // Maps Flutter cloth type values to FASHN backend category names
  static String _toFashnCategory(String clothType) {
    switch (clothType) {
      case 'upper':  return 'tops';
      case 'lower':  return 'bottoms';
      case 'overall': return 'one-pieces';
      default:       return 'tops';
    }
  }
}
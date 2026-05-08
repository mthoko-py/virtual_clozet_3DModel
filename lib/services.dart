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
  // Uses async job pattern: POST starts the job, then polls /status/<id>
  Future<TryOnResult?> tryOn3D({
    required File personPhoto,
    required File garmentImage,
    required String clothType,
    int numSteps = 20,
    double guidanceScale = 2.5,
    int seed = 42,
    void Function(String)? onProgress,
  }) async {
    try {
      // ── Step 1: submit job ──────────────────────────────────
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

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final startResp = await http.Response.fromStream(streamed);

      if (startResp.statusCode != 200) {
        onProgress?.call('Server error: ${startResp.statusCode}');
        return null;
      }

      final startData = jsonDecode(startResp.body) as Map<String, dynamic>;
      final jobId = startData['job_id'] as String?;
      if (jobId == null) {
        onProgress?.call('Error: server did not return a job_id');
        return null;
      }

      // ── Step 2: poll until done ─────────────────────────────
      onProgress?.call('Processing... (sampling ~5 min, please wait)');

      Map<String, dynamic>? resultData;
      int elapsed = 0;
      while (elapsed < 20 * 60) {
        await Future.delayed(const Duration(seconds: 6));
        elapsed += 6;

        final poll = await http
            .get(Uri.parse('$_baseUrl/status/$jobId'),
                headers: {'ngrok-skip-browser-warning': 'true'})
            .timeout(const Duration(seconds: 15));

        if (poll.statusCode != 200) continue;

        final pollData = jsonDecode(poll.body) as Map<String, dynamic>;
        final status = pollData['status'] as String?;

        if (status == 'done') {
          resultData = pollData;
          break;
        } else if (status == 'error') {
          onProgress?.call('Error: ${pollData['error']}');
          return null;
        } else {
          final step = pollData['step'] as String? ?? 'Processing...';
          onProgress?.call('$step (${elapsed ~/ 60}m ${elapsed % 60}s)');
        }
      }

      if (resultData == null) {
        onProgress?.call('Timed out after 20 minutes');
        return null;
      }

      // ── Step 3: download GLB ────────────────────────────────
      final tryon2d = base64Decode(resultData['tryon_2d_base64'] as String);

      onProgress?.call('Downloading 3D model...');
      final glbResp = await http
          .get(Uri.parse(resultData['glb_url'] as String),
              headers: {'ngrok-skip-browser-warning': 'true'})
          .timeout(const Duration(minutes: 3));

      if (glbResp.statusCode != 200) {
        onProgress?.call('GLB download failed: ${glbResp.statusCode}');
        return null;
      }

      onProgress?.call('Done! ${resultData['message'] ?? 'Try-on complete'}');

      return TryOnResult(
        tryon2dBytes: tryon2d,
        glbBytes: glbResp.bodyBytes,
        message: resultData['message'] as String? ?? 'Done',
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
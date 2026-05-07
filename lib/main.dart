// main.dart
// Virtual Clozet — Full pipeline Flutter app
// Dependencies needed in pubspec.yaml:
//   image_picker: ^1.1.2
//   model_viewer_plus: ^1.7.2
//   http: ^1.2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'services.dart';

void main() => runApp(const VirtualClozetApp());

// ─────────────────────────────────────────────────────────────
class VirtualClozetApp extends StatelessWidget {
  const VirtualClozetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Virtual Clozet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        scaffoldBackgroundColor: const Color(0xFFF8F8F8),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const TryOnPage(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MAIN PAGE
// ─────────────────────────────────────────────────────────────
class TryOnPage extends StatefulWidget {
  const TryOnPage({super.key});

  @override
  State<TryOnPage> createState() => _TryOnPageState();
}

class _TryOnPageState extends State<TryOnPage> {
  final VirtualClozetService _service = VirtualClozetService();
  final ImagePicker _picker = ImagePicker();

  File? _personPhoto;
  File? _garmentImage;

  // Results
  Uint8List? _tryon2dBytes;
  File?      _glbFile;

  String  _status      = 'Checking server connection...';
  bool    _connected   = false;
  bool    _isProcessing = false;
  String  _clothType   = 'upper';

  // UI tabs: 0=setup, 1=2D result, 2=3D model
  int _resultTab = 0;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    setState(() => _status = 'Connecting to server...');
    final info = await _service.healthCheck();
    if (mounted) {
      setState(() {
        _connected = info != null;
        _status = _connected
            ? '✅ Connected — upload images to begin'
            : '❌ Cannot connect. Update the URL in services.dart';
      });
    }
  }

  Future<void> _pick(bool isPerson, ImageSource source) async {
    final xf = await _picker.pickImage(source: source, imageQuality: 85,
        maxWidth: 1280, maxHeight: 1280);
    if (xf == null) return;
    setState(() {
      if (isPerson) {
        _personPhoto  = File(xf.path);
      } else {
        _garmentImage = File(xf.path);
      }
      _tryon2dBytes = null;
      _glbFile      = null;
      _resultTab    = 0;
    });
  }

  Future<void> _runPipeline() async {
    if (_personPhoto == null || _garmentImage == null) return;
    setState(() { _isProcessing = true; _resultTab = 0; });

    final result = await _service.tryOn3D(
      personPhoto:  _personPhoto!,
      garmentImage: _garmentImage!,
      clothType:    _clothType,
      onProgress: (msg) {
        if (mounted) setState(() => _status = msg);
      },
    );

    if (!mounted) return;

    if (result != null) {
      final glbFile = await _service.saveGlbToTemp(result.glbBytes);
      setState(() {
        _tryon2dBytes = result.tryon2dBytes;
        _glbFile      = glbFile;
        _resultTab    = 2; // jump to 3D tab
        _status       = result.message;
      });
    } else {
      setState(() => _status = 'Try-on failed. Check console.');
    }

    setState(() => _isProcessing = false);
  }

  void _clear() {
    setState(() {
      _personPhoto  = null;
      _garmentImage = null;
      _tryon2dBytes = null;
      _glbFile      = null;
      _resultTab    = 0;
      _status       = _connected
          ? '✅ Connected — upload images to begin'
          : '❌ Cannot connect. Update the URL in services.dart';
    });
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _statusBar(),
          if (_isProcessing) const LinearProgressIndicator(
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation(Colors.black)),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
    title: const Text('Virtual Clozet',
        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    elevation: 0,
    bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200)),
    actions: [
      IconButton(
        icon: Icon(Icons.wifi_tethering,
            color: _connected ? Colors.green : Colors.red),
        onPressed: _checkConnection,
        tooltip: 'Check connection',
      ),
      IconButton(
        icon: const Icon(Icons.clear_all),
        onPressed: _isProcessing ? null : _clear,
        tooltip: 'Clear all',
      ),
    ],
  );

  Widget _statusBar() => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: _isProcessing
        ? Colors.amber.shade50
        : (_connected ? Colors.green.shade50 : Colors.red.shade50),
    child: Row(
      children: [
        if (_isProcessing) ...[
          const SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.black))),
          const SizedBox(width: 10),
        ],
        Expanded(child: Text(_status,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade800))),
      ],
    ),
  );

  Widget _buildBody() {
    // If we have results, show tabbed view
    if (_glbFile != null || _tryon2dBytes != null) {
      return _resultView();
    }
    return _setupView();
  }

  // ── Setup view ─────────────────────────────────────────────
  Widget _setupView() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      // Person photo + Clothing image side by side
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(step: '1', label: 'Person Photo'),
                const SizedBox(height: 10),
                _ImageSelector(
                  image: _personPhoto,
                  aspectRatio: 3 / 4,
                  placeholder: Icons.person_add_alt_1,
                  hint: 'Tap to select person photo',
                  onPick: (src) => _pick(true, src),
                  disabled: _isProcessing,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(step: '2', label: 'Clothing Image'),
                const SizedBox(height: 10),
                _ImageSelector(
                  image: _garmentImage,
                  aspectRatio: 3 / 4,
                  placeholder: Icons.checkroom,
                  hint: 'Tap to select clothing\n(flat-lay or product photo)',
                  onPick: (src) => _pick(false, src),
                  disabled: _isProcessing,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      _divider(),
      const SizedBox(height: 20),

      // Cloth type
      _ClothTypeSelector(
        selected: _clothType,
        onChanged: _isProcessing ? null : (v) => setState(() => _clothType = v),
      ),
      const SizedBox(height: 28),

      // Action buttons
      _ActionButtons(
        canRun: _personPhoto != null && _garmentImage != null
            && !_isProcessing && _connected,
        isProcessing: _isProcessing,
        onTryOn: _runPipeline,
        onClear: _clear,
      ),
      const SizedBox(height: 32),
    ]),
  );

  // ── Result view ────────────────────────────────────────────
  Widget _resultView() {
    return Column(
      children: [
        // Tab bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _ResultTab(label: '⚙️ Setup', index: 0, current: _resultTab,
                onTap: (i) => setState(() => _resultTab = i)),
            const SizedBox(width: 8),
            if (_tryon2dBytes != null)
              _ResultTab(label: '🖼️ 2D Result', index: 1, current: _resultTab,
                  onTap: (i) => setState(() => _resultTab = i)),
            const SizedBox(width: 8),
            if (_glbFile != null)
              _ResultTab(label: '🧊 3D Model', index: 2, current: _resultTab,
                  onTap: (i) => setState(() => _resultTab = i)),
          ]),
        ),
        Divider(height: 1, color: Colors.grey.shade200),

        // Tab content
        Expanded(child: _tabContent()),
      ],
    );
  }

  Widget _tabContent() {
    switch (_resultTab) {
      case 0: return _setupView();
      case 1: return _Preview2D(bytes: _tryon2dBytes!);
      case 2: return _ModelViewer3D(glbFile: _glbFile!);
      default: return const SizedBox.shrink();
    }
  }

  Widget _divider() => Divider(color: Colors.grey.shade200, thickness: 1);
}

// ─────────────────────────────────────────────────────────────
// 2D PREVIEW
// ─────────────────────────────────────────────────────────────
class _Preview2D extends StatelessWidget {
  final Uint8List bytes;
  const _Preview2D({required this.bytes});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text('2D Try-On Result',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tap the "3D Model" tab to see the full 3D result.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 3D MODEL VIEWER
// ─────────────────────────────────────────────────────────────
class _ModelViewer3D extends StatefulWidget {
  final File glbFile;
  const _ModelViewer3D({required this.glbFile});

  @override
  State<_ModelViewer3D> createState() => _ModelViewer3DState();
}

class _ModelViewer3DState extends State<_ModelViewer3D> {
  bool _arEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ModelViewer(
          src: 'file://${widget.glbFile.path}',
          alt: 'Virtual try-on 3D model',
          ar: _arEnabled,
          arModes: const ['scene-viewer', 'webxr', 'quick-look'],
          autoRotate: true,
          autoRotateDelay: 1500,
          cameraControls: true,
          shadowIntensity: 1.0,
          shadowSoftness: 1.0,
          exposure: 1.0,
          backgroundColor: const Color(0xFFF0F0F0),
          // Nice initial camera angle
          cameraOrbit: '0deg 75deg 2m',
          fieldOfView: '30deg',
        ),

        // Controls overlay
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '👆 Drag to rotate  •  Pinch to zoom',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _arEnabled = !_arEnabled),
                  icon: const Icon(Icons.view_in_ar, size: 18),
                  label: Text(_arEnabled ? 'Disable AR' : 'View in AR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String step;
  final String label;
  const _SectionHeader({required this.step, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: Colors.black, borderRadius: BorderRadius.circular(6)),
        child: Text(step,
            style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.bold, letterSpacing: 0.3)),
      ),
    ],
  );
}

class _ImageSelector extends StatelessWidget {
  final File? image;
  final double aspectRatio;
  final IconData placeholder;
  final String hint;
  final void Function(ImageSource) onPick;
  final bool disabled;

  const _ImageSelector({
    required this.image,
    required this.aspectRatio,
    required this.placeholder,
    required this.hint,
    required this.onPick,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: disabled ? null : () => onPick(ImageSource.gallery),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: image != null
                        ? Colors.black
                        : Colors.grey.shade300,
                    width: image != null ? 2 : 1.5),
                image: image != null
                    ? DecorationImage(
                        image: FileImage(image!), fit: BoxFit.cover)
                    : null,
              ),
              child: image == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(placeholder,
                            size: 52, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(hint,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 13,
                                height: 1.5)),
                      ],
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _PickButton(
            icon: Icons.camera_alt,
            label: 'Camera',
            onTap: disabled ? null : () => onPick(ImageSource.camera)),
      ],
    );
  }
}

class _PickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _PickButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
}

class _ClothTypeSelector extends StatelessWidget {
  final String selected;
  final void Function(String)? onChanged;
  const _ClothTypeSelector({required this.selected, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Clothing Type',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                letterSpacing: 0.5)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white),
          child: Row(
            children: [
              _TypeBtn(label: 'Upper', value: 'upper',
                  icon: Icons.checkroom, selected: selected, onTap: onChanged),
              _vDivider(),
              _TypeBtn(label: 'Lower', value: 'lower',
                  icon: Icons.straighten, selected: selected, onTap: onChanged),
              _vDivider(),
              _TypeBtn(label: 'Overall', value: 'overall',
                  icon: Icons.category, selected: selected, onTap: onChanged),
            ],
          ),
        ),
      ],
    );
  }

  Widget _vDivider() => Container(
      width: 1, height: 48, color: Colors.grey.shade200);
}

class _TypeBtn extends StatelessWidget {
  final String label, value, selected;
  final IconData icon;
  final void Function(String)? onTap;
  const _TypeBtn({required this.label, required this.value,
      required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return Expanded(
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(value),
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
              color: active ? Colors.black : Colors.transparent,
              borderRadius: BorderRadius.circular(11)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17,
                  color: active ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : Colors.grey.shade700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final bool canRun, isProcessing;
  final VoidCallback onTryOn, onClear;
  const _ActionButtons({required this.canRun, required this.isProcessing,
      required this.onTryOn, required this.onClear});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 3,
        child: SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: canRun ? onTryOn : null,
            style: ElevatedButton.styleFrom(
              disabledBackgroundColor: Colors.grey.shade300,
            ),
            child: Text(
              isProcessing ? 'PROCESSING...' : '✨ TRY ON IN 3D',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold,
                  letterSpacing: 1.1),
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 1,
        child: SizedBox(
          height: 54,
          child: OutlinedButton(
            onPressed: isProcessing ? null : onClear,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              side: BorderSide(color: Colors.grey.shade300, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Icon(Icons.clear_all),
          ),
        ),
      ),
    ],
  );
}

class _ResultTab extends StatelessWidget {
  final String label;
  final int index, current;
  final void Function(int) onTap;
  const _ResultTab({required this.label, required this.index,
      required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = index == current;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.black : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color: active ? Colors.white : Colors.grey.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            )),
      ),
    );
  }
}
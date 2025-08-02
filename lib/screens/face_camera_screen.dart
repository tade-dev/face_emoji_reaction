import 'package:camera/camera.dart';
import 'package:face_emoji_reaction/services/face_detection_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceCameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FaceCameraScreen({super.key, required this.cameras});

  @override
  State<FaceCameraScreen> createState() => _FaceCameraScreenState();
}

class _FaceCameraScreenState extends State<FaceCameraScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  late FaceDetectorService _faceService;
  List<Face> _faces = [];
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _showStats = false;
  int _facesDetected = 0;
  double _averageSmile = 0.0;
  
  late AnimationController _pulseController;
  late AnimationController _scanController;
  late AnimationController _statsController;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _faceService = FaceDetectorService();
    _initCamera();
  }

  void _initControllers() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scanController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _statsController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  void _initCamera() async {
    try {
      _controller = CameraController(
        widget.cameras.first, 
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      
      await _controller!.initialize();
      _controller!.startImageStream(_processCameraImage);
      
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  InputImageFormat _getImageFormat(CameraImage image) {
    switch (image.format.raw) {
      case 35:
        return InputImageFormat.yuv420;
      case 17: 
        return InputImageFormat.nv21;
      default:
        return InputImageFormat.yuv420;
    }
  }

  InputImageRotation _getRotation() {
    if (_controller == null) return InputImageRotation.rotation0deg;
    
    final orientations = {
      DeviceOrientation.portraitUp: InputImageRotation.rotation0deg,
      DeviceOrientation.landscapeLeft: InputImageRotation.rotation90deg,
      DeviceOrientation.portraitDown: InputImageRotation.rotation180deg,
      DeviceOrientation.landscapeRight: InputImageRotation.rotation270deg,
    };
    
    return orientations[_controller!.value.deviceOrientation] ?? 
           InputImageRotation.rotation0deg;
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (var plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }

      final bytes = allBytes.done().buffer.asUint8List();
      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      
      final InputImageRotation rotation = _getRotation();
      final InputImageFormat format = _getImageFormat(image);

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
      final faces = await _faceService.detectFaces(inputImage);

      if (mounted) {
        setState(() {
          _faces = faces;
          _facesDetected = faces.length;
          _averageSmile = _calculateAverageSmile(faces);
        });
      }
    } catch (e) {
      debugPrint("Face detection error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  double _calculateAverageSmile(List<Face> faces) {
    if (faces.isEmpty) return 0.0;
    double totalSmile = 0.0;
    int count = 0;
    
    for (var face in faces) {
      if (face.smilingProbability != null) {
        totalSmile += face.smilingProbability!;
        count++;
      }
    }
    
    return count > 0 ? totalSmile / count : 0.0;
  }

  void _toggleStats() {
    setState(() {
      _showStats = !_showStats;
    });
    
    if (_showStats) {
      _statsController.forward();
    } else {
      _statsController.reverse();
    }
  }

  void _switchCamera() async {
    if (widget.cameras.length < 2) return;
    
    final currentIndex = widget.cameras.indexOf(_controller!.description);
    final nextIndex = (currentIndex + 1) % widget.cameras.length;
    
    await _controller?.dispose();
    
    _controller = CameraController(
      widget.cameras[nextIndex], 
      ResolutionPreset.medium,
      enableAudio: false,
    );
    
    await _controller!.initialize();
    _controller!.startImageStream(_processCameraImage);
    
    if (mounted) setState(() {});
  }

  Widget _buildScanningOverlay() {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, child) {
        return CustomPaint(
          painter: ScanLinePainter(_scanController.value),
          size: Size.infinite,
        );
      },
    );
  }

  Widget _buildStatsPanel() {
    return Positioned(
      top: 100,
      right: 16,
      child: AnimatedBuilder(
        animation: _statsController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(300 * (1 - _statsController.value), 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Face Stats",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow("Faces", _facesDetected.toString(), Icons.face),
                  const SizedBox(height: 8),
                  _buildStatRow(
                    "Happiness", 
                    "${(_averageSmile * 100).toInt()}%", 
                    Icons.sentiment_very_satisfied,
                  ),
                  const SizedBox(height: 8),
                  _buildStatRow(
                    "Status", 
                    _faces.isNotEmpty ? "Active" : "Scanning", 
                    Icons.radar,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: Icons.analytics,
            onPressed: _toggleStats,
            isActive: _showStats,
            tooltip: "Toggle Stats",
          )
              .animate()
              .fadeIn(duration: 800.ms, delay: 200.ms)
              .slideX(begin: -0.5, end: 0, duration: 600.ms, delay: 200.ms),
          
          _buildControlButton(
            icon: Icons.flip_camera_ios,
            onPressed: _switchCamera,
            tooltip: "Switch Camera",
          )
              .animate()
              .fadeIn(duration: 800.ms, delay: 400.ms)
              .slideX(begin: 0.5, end: 0, duration: 600.ms, delay: 400.ms),
          
          _buildControlButton(
            icon: Icons.close,
            onPressed: () => Navigator.pop(context),
            tooltip: "Close",
          )
              .animate()
              .fadeIn(duration: 800.ms, delay: 600.ms)
              .slideX(begin: 0.5, end: 0, duration: 600.ms, delay: 600.ms),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool isActive = false,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = isActive ? 1.0 + (_pulseController.value * 0.1) : 1.0;
          return Transform.scale(
            scale: scale,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive 
                    ? Colors.deepPurple.withOpacity(0.9)
                    : Colors.black.withOpacity(0.7),
                border: Border.all(
                  color: isActive 
                      ? Colors.deepPurple.withOpacity(0.5)
                      : Colors.white.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isActive 
                        ? Colors.deepPurple.withOpacity(0.4)
                        : Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: onPressed,
                icon: Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
                padding: const EdgeInsets.all(16),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Positioned(
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (_pulseController.value * 0.05),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _faces.isNotEmpty 
                      ? Colors.green.withOpacity(0.9)
                      : Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: (_faces.isNotEmpty ? Colors.green : Colors.orange)
                          .withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _faces.isNotEmpty ? Icons.face : Icons.search,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _faces.isNotEmpty 
                          ? "${_faces.length} face${_faces.length == 1 ? '' : 's'} detected"
                          : "Scanning for faces...",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 1000.ms, delay: 300.ms)
        .slideY(begin: -0.5, end: 0, duration: 800.ms, delay: 300.ms);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanController.dispose();
    _statsController.dispose();
    _controller?.dispose();
    _faceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.deepPurple),
                  strokeWidth: 3,
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .rotate(duration: 1.seconds),
              ),
              const SizedBox(height: 24),
              Text(
                "Initializing Face Detection...",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade300,
                  fontWeight: FontWeight.w500,
                ),
              )
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .fadeIn(duration: 1.seconds),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          SizedBox.expand(
            child: CameraPreview(_controller!)
                .animate()
                .fadeIn(duration: 1000.ms)
                .scaleXY(begin: 1.1, end: 1.0, duration: 1000.ms),
          ),
          
          _buildScanningOverlay(),
          
          CustomPaint(
            painter: AnimatedFaceEmojiPainter(_faces, _pulseController),
            child: Container(),
          ),
          
          _buildStatusIndicator(),
          
          if (_showStats) _buildStatsPanel(),
          
          _buildControlButtons(),
        ],
      ),
    );
  }
}

class ScanLinePainter extends CustomPainter {
  final double progress;

  ScanLinePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          Colors.deepPurple.withOpacity(0.3),
          Colors.deepPurple.withOpacity(0.8),
          Colors.deepPurple.withOpacity(0.3),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 4))
      ..strokeWidth = 4;

    final y = size.height * progress;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class AnimatedFaceEmojiPainter extends CustomPainter {
  final List<Face> faces;
  final AnimationController pulseController;

  AnimatedFaceEmojiPainter(this.faces, this.pulseController)
      : super(repaint: pulseController);

  @override
  void paint(Canvas canvas, Size size) {
    for (var face in faces) {
      final rect = face.boundingBox;

      // Determine emoji based on face analysis
      String emoji = "🙂";
      Color backgroundColor = Colors.blue;
      
      if (face.smilingProbability != null && face.smilingProbability! > 0.7) {
        emoji = "😄";
        backgroundColor = Colors.green;
      } else if (face.smilingProbability != null && face.smilingProbability! < 0.3) {
        emoji = "😐";
        backgroundColor = Colors.orange;
      } else if (face.leftEyeOpenProbability != null && 
                 face.rightEyeOpenProbability != null &&
                 face.leftEyeOpenProbability! < 0.4 && 
                 face.rightEyeOpenProbability! < 0.4) {
        emoji = "😴";
        backgroundColor = Colors.purple;
      }

      // Animated scale based on pulse
      final scale = 1.0 + (pulseController.value * 0.2);
      
      // Draw background circle
      final center = Offset(
        rect.left + rect.width / 2,
        rect.top + rect.height / 2,
      );
      
      final backgroundPaint = Paint()
        ..color = backgroundColor.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        center,
        (rect.width / 2) * scale,
        backgroundPaint,
      );

      // Draw border
      final borderPaint = Paint()
        ..color = backgroundColor.withOpacity(0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      
      canvas.drawCircle(
        center,
        (rect.width / 2) * scale,
        borderPaint,
      );

      // Draw emoji
      final textSpan = TextSpan(
        text: emoji,
        style: TextStyle(
          fontSize: 40 * scale,
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          center.dx - textPainter.width / 2,
          center.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
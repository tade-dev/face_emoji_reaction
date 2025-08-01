import 'package:camera/camera.dart';
import 'package:face_emoji_reaction/services/face_detection_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceCameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FaceCameraScreen({super.key, required this.cameras});

  @override
  State<FaceCameraScreen> createState() => _FaceCameraScreenState();
}

class _FaceCameraScreenState extends State<FaceCameraScreen> {
  late CameraController _controller;
  late FaceDetectorService _faceService;
  List<Face> _faces = [];

  @override
  void initState() {
    super.initState();
    _faceService = FaceDetectorService();
    _initCamera();
  }

  void _initCamera() async {
    _controller = CameraController(widget.cameras.first, ResolutionPreset.medium);
    await _controller.initialize();
    _controller.startImageStream(_processCameraImage);
    setState(() {});
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
    final orientations = {
      DeviceOrientation.portraitUp: InputImageRotation.rotation0deg,
      DeviceOrientation.landscapeLeft: InputImageRotation.rotation90deg,
      DeviceOrientation.portraitDown: InputImageRotation.rotation180deg,
      DeviceOrientation.landscapeRight: InputImageRotation.rotation270deg,
    };
    
    return orientations[_controller.value.deviceOrientation] ?? 
           InputImageRotation.rotation0deg;
  }

  void _processCameraImage(CameraImage image) async {
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
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_controller),
          CustomPaint(
            painter: FaceEmojiPainter(_faces),
            child: Container(),
          ),
        ],
      ),
    );
  }
}

class FaceEmojiPainter extends CustomPainter {
  final List<Face> faces;

  FaceEmojiPainter(this.faces);

  @override
  void paint(Canvas canvas, Size size) {

    for (var face in faces) {
      final rect = face.boundingBox;

      String emoji = "🙂";
      if (face.smilingProbability != null && face.smilingProbability! > 0.7) {
        emoji = "😄";
      } else if (face.leftEyeOpenProbability != null && face.leftEyeOpenProbability! < 0.4) {
        emoji = "😴";
      }

      final textSpan = TextSpan(text: emoji, style: TextStyle(fontSize: 40));
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(rect.left, rect.top));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
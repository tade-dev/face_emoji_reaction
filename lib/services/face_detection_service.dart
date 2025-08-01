import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorService {
  final options = FaceDetectorOptions(
    enableContours: true,
    enableLandmarks: true,
    enableClassification: true,
  );

  final faceDetector = FaceDetector(options: FaceDetectorOptions(
    enableClassification: true,
    enableLandmarks: true,
    enableContours: true,
  ));

  Future<List<Face>> detectFaces(InputImage image) async {
    return await faceDetector.processImage(image);
  }

  void dispose() {
    faceDetector.close();
  }
}
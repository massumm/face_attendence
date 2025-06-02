import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:face_attendance/sheets_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_recognition_service.dart';

late List<CameraDescription> cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  await SheetsService.init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override


  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Attendance',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: CameraHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ========== COMBINED CAMERA + HOME SCREEN ==========
class CameraHomeScreen extends StatefulWidget {
  @override
  _CameraHomeScreenState createState() => _CameraHomeScreenState();
}

class _CameraHomeScreenState extends State<CameraHomeScreen> {
  late CameraController _controller;
  String? _resultText;
  bool _isReady = false;
  final FaceRecognitionService recognizer = FaceRecognitionService();
  bool _isProcessing = false;
  bool _isRegistering = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(cameras[1], ResolutionPreset.medium);
    await _controller.initialize();
    if (!mounted) return;
    setState(() => _isReady = true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _captureFace() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final XFile picture = await _controller.takePicture();
    final inputImage = InputImage.fromFilePath(picture.path);

    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    final List<Face> faces = await faceDetector.processImage(inputImage);
    if (faces.isEmpty) {
      _showSnackBar("No face detected.");
      await faceDetector.close();
      setState(() => _isProcessing = false);
      return;
    }

    final ui.Image image =
    await decodeImageFromList(File(picture.path).readAsBytesSync());
    final Rect rect = faces.first.boundingBox;
    final cropped = await _cropFace(image, rect);

    final directory = await getApplicationDocumentsDirectory();
    final facePath =
        '${directory.path}/face_${DateTime.now().millisecondsSinceEpoch}.png';
    final faceFile = await File(facePath).writeAsBytes(cropped);

    await faceDetector.close();
    await _handleRecognitionOrRegistration(faceFile);

    setState(() => _isProcessing = false);
  }

  Future<void> _handleRecognitionOrRegistration(File faceFile) async {
    if (_isRegistering) {
      String? name = await _askNameDialog(context);
      if (name != null && name.isNotEmpty) {
        await recognizer.registerFace(name, faceFile);
        _showSnackBar("Registered $name");
      }
    } else {
      final matched = await recognizer.recognizeFace(faceFile);
      if (matched != null) {
        await SheetsService.insertAttendance(matched);
      }
      _showSnackBar(
          matched != null ? 'Hello $matched' : 'Face not recognized');
    }
  }

  Future<List<int>> _cropFace(ui.Image image, Rect rect) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    final src = Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
    final dst = Rect.fromLTWH(0, 0, rect.width, rect.height);

    canvas.drawImageRect(image, src, dst, paint);

    final pic = recorder.endRecording();
    final croppedImage =
    await pic.toImage(rect.width.toInt(), rect.height.toInt());
    final byteData =
    await croppedImage.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  Future<String?> _askNameDialog(BuildContext context) async {
    String input = "";
    return showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text("Enter name"),
          content: TextField(
            onChanged: (val) => input = val,
            decoration: InputDecoration(hintText: "Name"),
          ),
          actions: [
            TextButton(
              child: Text("Cancel"),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: Text("Save"),
              onPressed: () => Navigator.pop(context, input),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String msg) {
    setState(() {
      _resultText = "$msg";
    });
    Future.delayed(Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _resultText = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isReady
          ?
      Stack(
        children: [
          CameraPreview(_controller),

          // Positioned buttons at bottom
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildStyledButton(
                                icon: Icons.person_add,
                                label: "Register",
                                onTap: () {
                                  _isRegistering = true;
                                  _captureFace();
                                },
                                color: Colors.blueAccent,
                              ),
                              const SizedBox(width: 20),
                              _buildStyledButton(
                                icon: Icons.login,
                                label: "Check-In",
                                onTap: () {
                                  _isRegistering = false;
                                  _captureFace();
                                },
                                color: Colors.greenAccent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Centered loading spinner
          if (_isProcessing)
            Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // Text message at top
          if (_resultText != null)
            Positioned(
              top: 250,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _resultText!,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      )

        : Center(child: CircularProgressIndicator()),
      backgroundColor: Colors.black,
    );
  }

  Widget _buildStyledButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: Colors.white,
        shadowColor: color,
        elevation: 10,
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      icon: Icon(icon),
      label: Text(label,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      onPressed: onTap,
    );
  }

}

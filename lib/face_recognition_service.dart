import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FaceRecognitionService {
  late Interpreter _interpreter;
  final int inputSize = 112;
  final Map<String, List<double>> _registered = {};

  FaceRecognitionService() {
    _loadModel();
    _loadRegisteredFaces();
  }

  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
    print('Model loaded');
  }

  Float32List _preprocess(img.Image image) {
    final input = Float32List(inputSize * inputSize * 3);
    int pixelIndex = 0;
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);
        input[pixelIndex++] = (r - 128) / 128.0;
        input[pixelIndex++] = (g - 128) / 128.0;
        input[pixelIndex++] = (b - 128) / 128.0;
      }
    }
    return input;
  }

  Future<List<double>> getEmbedding(File file) async {
    final rawImage = img.decodeImage(await file.readAsBytes())!;
    final resized = img.copyResizeCropSquare(rawImage, inputSize);
    final input = _preprocess(resized);
    final output = List.filled(192, 0).reshape([1, 192]);
    _interpreter.run(input.reshape([1, 112, 112, 3]), output);
    return List<double>.from(output[0]);
  }

  double compare(List<double> a, List<double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dot / (sqrt(normA) * sqrt(normB));
  }

  // 🧠 Register and persist face embedding
  Future<void> registerFace(String name, File file) async {
    final embedding = await getEmbedding(file);
    _registered[name] = embedding;
    await _saveRegisteredFaces();
    print('User "$name" registered and saved.');
  }

  // 🔍 Recognize
  Future<String?> recognizeFace(File file, {double threshold = 0.5}) async {
    final embedding = await getEmbedding(file);
    String? bestMatch;
    double bestScore = -1;

    _registered.forEach((name, savedEmbedding) {
      final similarity = compare(embedding, savedEmbedding);
      if (similarity > bestScore) {
        bestScore = similarity;
        bestMatch = name;
      }
    });

    if (bestScore >= threshold) {
      print('Best match: $bestMatch (similarity: $bestScore)');
      return bestMatch;
    } else {
      print('No match found (best similarity: $bestScore)');
      return null;
    }
  }

  // 📥 Load saved embeddings from SharedPreferences
  Future<void> _loadRegisteredFaces() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      final jsonString = prefs.getString(key);
      if (jsonString != null) {
        final List<dynamic> list = jsonDecode(jsonString);
        _registered[key] = list.cast<double>();
      }
    }
    print('Loaded registered faces: ${_registered.keys}');
  }

  // 💾 Save embeddings to SharedPreferences
  Future<void> _saveRegisteredFaces() async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in _registered.entries) {
      final name = entry.key;
      final embedding = entry.value;
      await prefs.setString(name, jsonEncode(embedding));
    }
  }

  List<String> listRegisteredUsers() => _registered.keys.toList();

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _registered.clear();
    print('All registered users cleared.');
  }
}

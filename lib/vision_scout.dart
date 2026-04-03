import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'package:growlytics/main.dart'; // <-- Imports your team's remote control

class VisionScoutScreen extends StatefulWidget {
  const VisionScoutScreen({Key? key}) : super(key: key);

  @override
  _VisionScoutScreenState createState() => _VisionScoutScreenState();
}

class _VisionScoutScreenState extends State<VisionScoutScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isModelLoaded = false;
  String _resultText = "";
  double _confidence = 0.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadModel();
  }

  // 1. Initialize the Device Camera
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    // Default to the back camera (first in the list usually)
    final backCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);

    _cameraController = CameraController(backCamera, ResolutionPreset.high);
    await _cameraController!.initialize();
    
    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  // 2. Load the Teachable Machine Brain
  Future<void> _loadModel() async {
    String? res = await Tflite.loadModel(
      model: "assets/model.tflite", // <-- Ensure this matches your exact filename
      labels: "assets/labels.txt",
      isAsset: true,
      numThreads: 1, 
      useGpuDelegate: false,
    );
    print("Model Load Result: $res");
    setState(() {
      _isModelLoaded = true;
    });
  }

  // 3. The Scan Logic & 90% Bouncer
  Future<void> _scanPlant() async {
    if (!_cameraController!.value.isInitialized) return;

    try {
      // Snap the photo
      final XFile image = await _cameraController!.takePicture();

      // Run the AI on the photo (Floating Point configuration)
      var recognitions = await Tflite.runModelOnImage(
        path: image.path,
        imageMean: 127.5, 
        imageStd: 127.5,  
        numResults: 1, 
        threshold: 0.1, 
        asynch: true,
      );

      if (recognitions != null && recognitions.isNotEmpty) {
        double confidence = recognitions[0]['confidence'];
        String label = recognitions[0]['label'];

        setState(() {
           if (confidence > 0.90) {
             // PASS: Update the variables so the UI redraws correctly
             _confidence = confidence;
             _resultText = "Disease: $label\nConfidence: ${(confidence * 100).toStringAsFixed(1)}%";
           } else {
             // FAIL: Trigger the 90% Bouncer
             _confidence = 0.0;
             _resultText = "Plant not recognized clearly.\nPlease move closer and try again.";
           }
         });
      }
    } catch (e) {
      print("Error scanning plant: $e");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    Tflite.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Vision Scout'),
        backgroundColor: Colors.green[700],
      ),
      body: Column(
        children: [
          // The Camera Viewfinder
          Expanded(
            child: _isCameraInitialized
                ? Container(
                    margin: const EdgeInsets.all(16),
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: CameraPreview(_cameraController!),
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          
          // The Results & Action Area
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              children: [
                Text(
                  _resultText.isEmpty ? "Ready to scan." : _resultText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                
                // Scan Button
                ElevatedButton(
                  onPressed: (_isCameraInitialized && _isModelLoaded) ? _scanPlant : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Scan Plant', style: TextStyle(fontSize: 18)),
                ),
                
                const SizedBox(height: 10),

                // Link to Eco Prescription Tab (Only shows if confidence > 90%)
                if (_confidence > 0.90)
                  TextButton(
                    onPressed: () {
                      // Uses your team's remote control to jump to Tab 2
                      mainPageKey.currentState?.changeTab(2);
                    },
                    child: const Text('Get Eco Prescription →', style: TextStyle(color: Colors.green, fontSize: 16)),
                  )
              ],
            ),
          )
        ],
      ),
    );
  }
}
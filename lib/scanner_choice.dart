import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:growlytics/vision_scout.dart'; 

class ScannerChoicePage extends StatelessWidget {
  const ScannerChoicePage({super.key});

  Future<void> _launchWebScanner() async {
    final Uri url = Uri.parse('https://bloom-watcher-tech.lovable.app/scanner');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch web scanner');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F9F4),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose AI Scanner',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Select the diagnostic engine that best fits your current environment.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),

              // BUTTON 1: The Native App (Offline TFLite)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: const Color(0xFF4CAF50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const VisionScoutScreen()),
                  );
                },
                child: const Column(
                  children: [
                    Icon(Icons.camera_alt, size: 40, color: Colors.white),
                    SizedBox(height: 10),
                    Text(
                      'Native Vision Scout',
                      style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Offline • High Speed • Field Ready',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // BUTTON 2: The Web App (TF.js)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(20),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF4CAF50), width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: _launchWebScanner,
                child: const Column(
                  children: [
                    Icon(Icons.language, size: 40, color: Color(0xFF4CAF50)),
                    SizedBox(height: 10),
                    Text(
                      'Community Web Scanner',
                      style: TextStyle(fontSize: 20, color: Color(0xFF4CAF50), fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Cloud Powered • No App Required',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ), 
    ); 
  }
}
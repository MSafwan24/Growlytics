import 'package:flutter/material.dart';

class VisionScannerPage extends StatelessWidget{
    const VisionScannerPage({super.key});

    @override
    Widget build(BuildContext context) {
        return Scaffold(

            backgroundColor: Colors.black,
            appBar: AppBar(
                title: const Text("AI vision scanner",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
            ),

            //camera view be in here
            body: Stack(
                children: [
                    Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.grey.shade900,
                        child: const Center(
                            child: Icon(Icons.camera_alt, color: Colors.white24, size: 100),
                        ),
                    ),

                    //Target box area
                    Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                Container(
                                    width:260,
                                    height: 260,
                                    decoration: BoxDecoration(
                                        border: Border.all(color: Colors.greenAccent, width: 3),
                                        borderRadius: BorderRadius.circular(30),
                                    ),
                                ),
                                const SizedBox(height: 20),
                                Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical:8),
                                    decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text("Center the leaf inside the frame",
                                    style: TextStyle(color: Colors.white, fontSize: 14),
                                    ),
                                ),
                            ],
                        ),
                    ),

                    //flash toggle
                    Positioned(
                        top:20,
                        right:20,
                        child: _buildIconButton(Icons.flashlight_on, Colors.yellow, "Flash"),
                    ),

                    // Bottom control bar partt
                    Positioned(
                        bottom: 50,
                        left: 0,
                        right: 0,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                                //gallery access
                                _buildActionMenu(Icons.photo_library, "Gallery"),
                                // main shutter button
                                _buildShutterButton(),
                                // scan history
                                _buildActionMenu(Icons.history, "History"),

                            ],
                        ),
                    ),
                ],
            ),
        );
    }
    //small helper side icon
    Widget _buildActionMenu(IconData icon, String label){
        return Column(
            children: [
                CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white10,
                    child: Icon(icon, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 8),
                Text(label,style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
        );
    }

    //small helper top button
    Widget _buildIconButton(IconData icon, Color color, String label) {
        return CircleAvatar(
            backgroundColor: Colors.black45,
            child: Icon(icon, color: color, size: 24),
        );
    }

    //shutter button 
    Widget _buildShutterButton(){
        return Container(
            height: 85,
            width: 85,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
            ),
            child: Padding(
                padding: const EdgeInsets.all(5.0),
                child: Container(
                    decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.search, size: 40, color: Colors.green),
                ),
            ),
        );
    }
}
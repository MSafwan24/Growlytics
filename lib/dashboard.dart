import 'package:growlytics/visionscanner.dart';
import 'package:flutter/material.dart';
import 'package:growlytics/main.dart';

class DashboardPage extends StatelessWidget{
    const DashboardPage({super.key});

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            backgroundColor: const Color(0xFFF1F8E9),
            body: SafeArea(
                child: Padding(
                    padding : const EdgeInsets.all(24.0),
                    child : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            const Text("Growlytics", 
                                style : TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green)),
                            const Text("Your Personal AI Agronomist", 
                                style: TextStyle (color: Colors.grey)),
                            const SizedBox(height: 24),

                            //placeholder for now, later wiill be real time weather reader
                            _buildWeatherCard(),

                            const SizedBox(height: 24),

                            //scan button 
                            _buildScanButton(context),
                            const SizedBox(height: 32),

                            //Crops showing section
                            const Text("Your Crops",
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),

                            //scanned crops displayed following logic that only unique will be display
                            _buildCropCard("Tomato", "3 Scans", Icons.agriculture),
                            _buildCropCard("Watermelon", "1 Scan", Icons.water_drop),

                        ],
                    ),
                ),
            ),
        );
    }

    //Will follow real time 
    Widget _buildWeatherCard(){
        return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)] ),
            child: const Row(
                children: [
                    const Icon(Icons.wb_sunny, color: Colors.orange, size : 40),
                    const SizedBox(width: 20),

                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                                Text("32c - Sunny", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                Text("Smart Hydration: No rain expected",
                                softWrap: true,
                                ),
                            ],
                        ),
                    )
                ],
            ),
        );
    }

    //This is for the scan button will direct to visionscanner.dart
    Widget _buildScanButton(BuildContext context) {
        return SizedBox(

            width: double.infinity,
            height: 60,
            child:  ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),

                ),

                icon: const Icon(Icons.camera_alt),
                label: const Text("SCAN NOW", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: (){

                    // This logic tells main.dart  to change into visionscanner.dart when clicked
                    mainPageKey.currentState?.changeTab(1);
                },
            ),
        );
    }

    // Crops card template
    Widget _buildCropCard(String name, String count, IconData icon) {
        return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child: Row(
                children: [
                    CircleAvatar(
                        backgroundColor: Colors.green.shade100,
                        child: Icon(icon, color: Colors.green.shade700),
                    ),

                    const SizedBox(width: 16),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(count, style: const TextStyle(color: Colors.grey)),
                        ],
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                ],
            ),
        );
    }
}
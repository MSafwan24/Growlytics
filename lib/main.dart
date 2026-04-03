import 'package:flutter/material.dart';
import 'package:growlytics/dashboard.dart';
import 'package:growlytics/visionscanner.dart';
import 'package:growlytics/prescription.dart';
import 'package:growlytics/yieldpredictor.dart';
import 'package:growlytics/vision_scout.dart';

//Act as remote control
final GlobalKey<MainPageState> mainPageKey = GlobalKey<MainPageState>();


void main(){
  runApp(const GrowlyticsApp());

}

class GrowlyticsApp extends StatelessWidget {
  const GrowlyticsApp({super.key});

  @override 
  Widget build(BuildContext context){
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme : ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor : Colors.green),
        useMaterial3: true,
      ),
      home: MainPage(key: mainPageKey),
    );
  }
}

class MainPage extends StatefulWidget{
  const MainPage({super.key});

  @override
  State<MainPage> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  //func to change tab
  void changeTab(int index){
    setState(() {
      _selectedIndex = index;
    });
  }

  final List <Widget> _pages = [
    const DashboardPage(),
    const VisionScoutScreen(),
    const EcoPrescriptionPage(),
    const YieldPredictorPage(),
  ];

  @override 
  Widget build(BuildContext context){
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => changeTab(index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.green.shade700,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Scanneer'),
          BottomNavigationBarItem(icon: Icon(Icons.science), label: 'Eco'),
          BottomNavigationBarItem(icon: Icon(Icons.trending_up), label: 'Yield'),
        ],
      ),
    );
  }
}

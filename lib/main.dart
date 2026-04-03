import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:growlytics/dashboard.dart';
import 'package:growlytics/prescription.dart';
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

  //launch community hub url function
  Future<void> _launchCommunityHub()async{
    final Uri url = Uri.parse("https://growlytics-hub-community.lovable.app");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)){
      throw Exception ('Could not launch community hub');
    }
  }

  //func to change tab
  void changeTab(int index){
    if (index ==3){
      _launchCommunityHub();
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  final List <Widget> _pages = [
    const DashboardPage(),
    const VisionScoutScreen(),
    const EcoPrescriptionPage(),
    const SizedBox(),
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
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Scanner'),
          BottomNavigationBarItem(icon: Icon(Icons.science), label: 'Eco'),
          BottomNavigationBarItem(icon: Icon(Icons.groups), label: 'Community'),
        ],
      ),
    );
  }
}

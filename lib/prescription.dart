import 'package:flutter/material.dart';

class EcoPrescriptionPage extends StatelessWidget{
  const EcoPrescriptionPage({super.key});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      backgroundColor:const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text("Plant Doctor Library", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          const Text("Recent Diagnose", 
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(height: 16),

          //sample card1 and 2
          _buildDiagnosisSummaryCard(
            context,
            "Tomato",
            "Early Blight",
            Colors.orange,
            "Fungal infection detected on lower stems",
            ["Prune infected lower leaves", "Apply Copper based fungicide", "Avoid overhead watering"]
          ),

          _buildDiagnosisSummaryCard(
            context,
            "Watermelon",
            "Healthy",
            Colors.green,
            "No active diseases found. Growth is optimal",
            ["maintain current watering", "Cheeck for pests weekly"]
          ),
        ],
      ),
    );
  }

  //summary card part
  Widget _buildDiagnosisSummaryCard(
    BuildContext context, String plant, String disease, Color color, String diagnosisText, List<String> steps){
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(Icons.spa, color: color)),
        title: Text(plant, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(disease),
        trailing: IconButton(
          icon: const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.green),
          onPressed: () => _showPopup(context, plant, disease, color, diagnosisText, steps),
        ),
      ),
    );
  }

  //Popup on screen
  void _showPopup(BuildContext context, String plant, String disease, Color color, String diagnosisText, List<String> steps){
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context){

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Color(0xFFF1F8E9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),

          child: Column(
            children: [

              //top header banner for the diagnosis
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:[
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height:16),
                    Text(plant.toUpperCase(), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    Text(disease, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Diagnosis: $diagnosisText", style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Text("How to Cure", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold )),
                    const SizedBox(height: 16),

                    //generate card
                    for (int i = 0; i < steps.length; i++)
                    _buildStepCard((i+1).toString(), steps[i]),

                    const SizedBox(height: 24),
                    const Text("Recovery Needs", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildRecoveryStat("Soil pH", "6.2 (Slightly Acidic)", Icons.science),
                    _buildRecoveryStat("Calcium", "Low (Needs boost)", Icons.water_drop),

                    const SizedBox(height: 30),
                    // box area for tips
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue.shade200)),
                      child: Row(
                        children: [
                          const Icon(Icons.info, color:Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(child: Text("Tip: Ensure 2-3 feet spacing for airflow.", style: TextStyle(color: Colors.blue.shade900, fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              //clsoe button for popup
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    child: const Text("CLOSE REPORT", style: TextStyle(color:Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildStepCard(String number, String instruction){
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const[BoxShadow(color: Colors.black12, blurRadius: 2)]),
      child: Row(
        children: [
          CircleAvatar(radius: 14, backgroundColor: Colors.green.shade400, child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          Expanded(child: Text(instruction, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

    Widget _buildRecoveryStat(String label, String value, IconData icon){
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Row(
          children: [
            Icon(icon, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 12),
            Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }
  
}
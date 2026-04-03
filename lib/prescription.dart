import 'package:flutter/material.dart';
import 'plant_data.dart'; // Importing our new blueprint and mock database

class EcoPrescriptionPage extends StatefulWidget {
  const EcoPrescriptionPage({super.key});

  @override
  State<EcoPrescriptionPage> createState() => _EcoPrescriptionPageState();
}

class _EcoPrescriptionPageState extends State<EcoPrescriptionPage> {
  // 1. Set the initial plant to the first one in our mock database (Tomato)
  late PlantPrescription selectedPlant;

  // 2. Track which steps are completed dynamically
  Set<String> completedSteps = {};

  @override
  void initState() {
    super.initState();
    selectedPlant = mockDatabase[0]; // Defaults to Tomato on load
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: DropdownButtonHideUnderline(
          child: DropdownButton<PlantPrescription>(
            // This single line gives the popup menu the curved edges!
            borderRadius: BorderRadius.circular(20), 
            
            value: selectedPlant,
            icon: const Icon(Icons.arrow_drop_down, color: Colors.green, size: 30),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87),
            alignment: Alignment.center,
            items: mockDatabase.map((PlantPrescription plant) {
              return DropdownMenuItem<PlantPrescription>(
                value: plant,
                child: Text("${plant.plantName} Prescription"),
              );
            }).toList(),
            onChanged: (PlantPrescription? newValue) {
              if (newValue != null) {
                setState(() {
                  selectedPlant = newValue;
                  completedSteps.clear(); 
                });
              }
            },
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${selectedPlant.plantName} treatment plan saved!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        backgroundColor: Colors.green.shade700,
        icon: const Icon(Icons.save, color: Colors.white),
        label: const Text("Save Progress", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),

      body: ListView(
        padding: const EdgeInsets.all(20.0),
        physics: const BouncingScrollPhysics(),
        children: [
          const Text(
            "Current Soil Profile",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 16),

          // 4. Passes the dynamic plant data into the soil card
          _buildSoilHealthCard(),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Tailored Nutrient Plan",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
              ),
              // Dynamic counter based on the plant's total steps
              Text(
                "${completedSteps.length}/${selectedPlant.actionSteps.length} Done",
                style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.bold),
              )
            ],
          ),
          const SizedBox(height: 16),

          // 5. Dynamically generates the action steps using .map()
          ...selectedPlant.actionSteps.map((step) {
            bool isCompleted = completedSteps.contains(step.stepNumber);
            return _buildInteractiveStepCard(
              step.stepNumber,
              step.title,
              step.description,
              isCompleted,
              (newValue) {
                setState(() {
                  if (newValue == true) {
                    completedSteps.add(step.stepNumber);
                  } else {
                    completedSteps.remove(step.stepNumber);
                  }
                });
              },
            );
          }),

          const SizedBox(height: 24),
          const Text(
            "Eco-Countermeasures",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
          ),
          const SizedBox(height: 16),

          // 6. Dynamically generates the eco tips
          ...selectedPlant.ecoTips.map((tip) {
            return _buildExpandableTipCard(tip.title, tip.description, tip.icon);
          }),
          
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildSoilHealthCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Soil pH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              // Pulls pH from selected plant
              Text(selectedPlant.currentPh.toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange.shade700)),
            ],
          ),
          // Pulls status from selected plant
          Text(selectedPlant.phStatus, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Divider(height: 30),
          
          const Text("NPK Levels", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          // Pulls NPK levels from selected plant
          _buildNutrientBar("Nitrogen (N)", selectedPlant.nitrogenLevel, Colors.blue),
          _buildNutrientBar("Phosphorus (P)", selectedPlant.phosphorusLevel, Colors.purple),
          _buildNutrientBar("Potassium (K)", selectedPlant.potassiumLevel, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildNutrientBar(String label, double level, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: level,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveStepCard(String stepNumber, String title, String description, bool isCompleted, ValueChanged<bool?> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green.shade50 : Colors.white, 
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isCompleted ? Colors.green : Colors.green.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
      ),
      child: CheckboxListTile(
        value: isCompleted,
        onChanged: onChanged,
        activeColor: Colors.green.shade700,
        checkColor: Colors.white,
        title: Text(
          title, 
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            fontSize: 16,
            decoration: isCompleted ? TextDecoration.lineThrough : null, 
            color: isCompleted ? Colors.grey : Colors.black,
          )
        ),
        subtitle: Text(
          description, 
          style: TextStyle(
            color: isCompleted ? Colors.grey : Colors.grey.shade700, 
            fontSize: 14
          )
        ),
        secondary: CircleAvatar(
          radius: 16,
          backgroundColor: isCompleted ? Colors.grey : Colors.green.shade600,
          child: Text(stepNumber, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _buildExpandableTipCard(String title, String details, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent), 
        child: ExpansionTile(
          leading: Icon(icon, color: Colors.blue.shade600, size: 28),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
          iconColor: Colors.blue.shade700,
          collapsedIconColor: Colors.blue.shade700,
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          children: [
            Text(details, style: TextStyle(color: Colors.blue.shade800, fontSize: 14, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

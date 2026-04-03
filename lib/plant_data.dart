import 'package:flutter/material.dart';

// 1. Blueprint for a single Action Step
class ActionStep {
  final String stepNumber;
  final String title;
  final String description;

  ActionStep({
    required this.stepNumber,
    required this.title,
    required this.description,
  });
}

// 2. Blueprint for a single Eco Tip
class EcoTip {
  final String title;
  final String description;
  final IconData icon;

  EcoTip({
    required this.title,
    required this.description,
    required this.icon,
  });
}

// 3. The Main Blueprint for a Plant's Prescription
class PlantPrescription {
  final String plantName;
  final double currentPh;
  final String phStatus;
  final double nitrogenLevel;
  final double phosphorusLevel;
  final double potassiumLevel;
  final List<ActionStep> actionSteps;
  final List<EcoTip> ecoTips;

  PlantPrescription({
    required this.plantName,
    required this.currentPh,
    required this.phStatus,
    required this.nitrogenLevel,
    required this.phosphorusLevel,
    required this.potassiumLevel,
    required this.actionSteps,
    required this.ecoTips,
  });
}

// 4. Our Mock Database (List of PlantPrescriptions)
final List<PlantPrescription> mockDatabase = [
  
  // -- TOMATO DATA (The data we built earlier) --
  PlantPrescription(
    plantName: "Tomato",
    currentPh: 5.4,
    phStatus: "Acidic (Needs Calcium)",
    nitrogenLevel: 0.4,
    phosphorusLevel: 0.7,
    potassiumLevel: 0.6,
    actionSteps: [
      ActionStep(stepNumber: "1", title: "Adjust Soil pH", description: "Apply 2 lbs of agricultural limestone per 100 sq ft."),
      ActionStep(stepNumber: "2", title: "Boost Nitrogen Naturally", description: "Plant a cover crop of legumes to fix nitrogen safely."),
      ActionStep(stepNumber: "3", title: "Enhance Phosphorus", description: "Incorporate organic bone meal into the root zone."),
    ],
    ecoTips: [
      EcoTip(title: "Prevent Runoff", description: "Avoid applying fertilizers right before heavy rain.", icon: Icons.water_drop),
      EcoTip(title: "Mulching Strategy", description: "Apply a 2-inch layer of organic mulch around the base.", icon: Icons.nature),
      EcoTip(title: "Companion Planting", description: "Consider planting marigolds or basil near your main crops.", icon: Icons.local_florist),
      EcoTip(title: "Crop Rotation", description: "Do not plant the same crop family in this exact spot next season.", icon: Icons.autorenew),
    ],
  ),

  // -- WATERMELON DATA (New data to test the dropdown) --
  PlantPrescription(
    plantName: "Watermelon",
    currentPh: 6.5,
    phStatus: "Optimal (Maintain)",
    nitrogenLevel: 0.8,
    phosphorusLevel: 0.5,
    potassiumLevel: 0.9,
    actionSteps: [
      ActionStep(stepNumber: "1", title: "Maintain Potassium", description: "Apply kelp meal to support heavy fruiting stages."),
      ActionStep(stepNumber: "2", title: "Monitor Phosphorus", description: "Slight deficiency detected; add a light compost tea."),
    ],
    ecoTips: [
      EcoTip(title: "Drip Irrigation", description: "Switch to drip irrigation to avoid wetting the leaves and causing fungal rot.", icon: Icons.water),
      EcoTip(title: "Pollinator Friendly", description: "Avoid any natural pesticides during morning blooming hours.", icon: Icons.bug_report),
    ],
  ),
];

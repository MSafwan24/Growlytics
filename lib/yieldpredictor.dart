import 'package:flutter/material.dart';

class YieldPredictorPage extends StatelessWidget{
    const YieldPredictorPage({super.key});

    @override
    Widget build(BuildContext context){
        return Scaffold(
            appBar: AppBar(title: const Text("Yield Predictor")),
            body: const Center(child: Text("Harvest Forecasts")),
        );
    }
}
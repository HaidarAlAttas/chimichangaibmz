import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class PulseChartWidget extends StatelessWidget {
  final List<double> recentSamples;

  const PulseChartWidget({
    super.key,
    required this.recentSamples,
  });

  @override
  Widget build(BuildContext context) {
    if (recentSamples.isEmpty) {
      return Container(
        height: 90,
        alignment: Alignment.center,
        child: const Text(
          "Waiting for camera signal...",
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }

    final spots = <FlSpot>[];
    for (int i = 0; i < recentSamples.length; i++) {
      spots.add(FlSpot(i.toDouble(), recentSamples[i]));
    }

    // Determine min/max for dynamic scaling
    double minY = recentSamples.reduce((a, b) => a < b ? a : b);
    double maxY = recentSamples.reduce((a, b) => a > b ? a : b);
    if ((maxY - minY).abs() < 0.01) {
      minY -= 0.05;
      maxY += 0.05;
    }

    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF38BDF8),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "RAW rPPG BVP STREAM (30 FPS)",
                    style: TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const Text(
                "LinuxONE Egress Buffer",
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: spots.length.toDouble() > 1 ? spots.length.toDouble() - 1 : 1,
                minY: minY,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: const Color(0xFF38BDF8),
                    barWidth: 2.2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF38BDF8).withOpacity(0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

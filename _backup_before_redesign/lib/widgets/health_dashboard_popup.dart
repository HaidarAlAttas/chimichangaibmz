import 'package:flutter/material.dart';
import '../models/vital_results.dart';

/// ============================================================================
/// 🫀 POP-UP PATIENT HEALTH DASHBOARD (Step 3 in Architecture)
/// ============================================================================
/// Displays:
/// 1. Heart rate (e.g. 74 BPM)
/// 2. Blood oxygen level (e.g. 98.2% SpO2)
/// 3. Respiratory Rate (e.g. 16 breathing/min)
/// 4. Status & risk score (e.g. Normal (94%))
/// 5. Health reasoning (IBM Granite LLM clinical factor analysis)
/// ============================================================================

class HealthDashboardPopup extends StatelessWidget {
  final VitalResults results;
  final VoidCallback onDismiss;

  const HealthDashboardPopup({
    super.key,
    required this.results,
    required this.onDismiss,
  });

  static Future<void> show(BuildContext context, VitalResults results) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => HealthDashboardPopup(
        results: results,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Color _getRiskColor(String status) {
    switch (status.toLowerCase()) {
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'critical':
        return const Color(0xFFEF4444);
      case 'normal':
      default:
        return const Color(0xFF10B981);
    }
  }

  @override
  Widget build(BuildContext context) {
    final riskColor = _getRiskColor(results.riskStatus);

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.8),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0043CE).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF0043CE)),
                    ),
                    child: const Text("IBM", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Patient Health Dashboard",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "LinuxONE s390x &bull; Telum Inference",
                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 4 Vitals Grid
                  Row(
                    children: [
                      // 1. Heart Rate
                      Expanded(
                        child: _buildVitalCard(
                          title: "HEART RATE",
                          value: "${results.bpm.toStringAsFixed(0)}",
                          unit: "BPM",
                          icon: Icons.favorite,
                          iconColor: const Color(0xFFF87171),
                          bgColor: const Color(0xFFEF4444).withOpacity(0.1),
                          borderColor: const Color(0xFFEF4444).withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 2. Blood Oxygen
                      Expanded(
                        child: _buildVitalCard(
                          title: "BLOOD OXYGEN",
                          value: "${results.spo2.toStringAsFixed(1)}",
                          unit: "% SpO2",
                          icon: Icons.water_drop,
                          iconColor: const Color(0xFF38BDF8),
                          bgColor: const Color(0xFF0284C7).withOpacity(0.1),
                          borderColor: const Color(0xFF38BDF8).withOpacity(0.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      // 3. Respiratory Rate
                      Expanded(
                        child: _buildVitalCard(
                          title: "RESPIRATORY RATE",
                          value: "${results.respiratoryRate}",
                          unit: "breathing/min",
                          icon: Icons.air,
                          iconColor: const Color(0xFFA855F7),
                          bgColor: const Color(0xFFA855F7).withOpacity(0.1),
                          borderColor: const Color(0xFFA855F7).withOpacity(0.3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 4. Status & Risk Score
                      Expanded(
                        child: _buildVitalCard(
                          title: "STATUS & RISK",
                          value: results.riskStatus.toUpperCase(),
                          unit: "(${(results.riskConfidence * 100).toStringAsFixed(0)}%)",
                          icon: Icons.shield,
                          iconColor: riskColor,
                          bgColor: riskColor.withOpacity(0.1),
                          borderColor: riskColor.withOpacity(0.4),
                          isTextValue: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 5. Health Reasoning Box (Exact match to sketch #3)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0F1E4A),
                          const Color(0xFF060B19),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.5)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.15),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.psychology, color: Color(0xFFC084FC), size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  "IBM Granite Health Reasoning",
                                  style: TextStyle(
                                    color: Color(0xFFC084FC),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                "Explainable AI",
                                style: TextStyle(color: Colors.white70, fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          results.healthReasoning,
                          style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 13,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Divider(color: Colors.white12, height: 1),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  "Explainability: 100% transparent",
                                  style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            Text(
                              results.isMock ? "Demo Fallback" : "Live s390x Enclave",
                              style: TextStyle(
                                color: results.isMock ? Colors.amberAccent : const Color(0xFF38BDF8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Signal Quality & Enclave confirmation
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Signal Quality Index (SQI): ${(results.sqi * 100).toStringAsFixed(0)}%",
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        const Text(
                          "Encrypted via Secure Execution",
                          style: TextStyle(color: Color(0xFF34D399), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Done Action Button
          ElevatedButton(
            onPressed: onDismiss,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0043CE),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 4,
            ),
            child: const Text("Done &bull; Save to Health Record", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    bool isTextValue = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              Icon(icon, color: iconColor, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isTextValue ? 16 : 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(color: Colors.white70, fontSize: isTextValue ? 11 : 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

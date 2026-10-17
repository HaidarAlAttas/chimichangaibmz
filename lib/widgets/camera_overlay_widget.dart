import 'package:flutter/material.dart';

class CameraOverlayWidget extends StatelessWidget {
  final double progress;
  final bool isScanning;
  final int remainingSeconds;

  const CameraOverlayWidget({
    super.key,
    required this.progress,
    required this.isScanning,
    required this.remainingSeconds,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Darkened vignette background with transparent center oval for face
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.65),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  backgroundBlendMode: BlendMode.dstOut,
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 250,
                  height: 320,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(130),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Face outline guide border
        Align(
          alignment: Alignment.center,
          child: Container(
            width: 250,
            height: 320,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(130),
              border: Border.all(
                color: isScanning ? const Color(0xFF38BDF8) : Colors.white54,
                width: 2.5,
              ),
            ),
          ),
        ),

        // Scanning Status & Instruction Banner
        Positioned(
          top: 40,
          left: 20,
          right: 20,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isScanning ? Colors.greenAccent : Colors.amberAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isScanning 
                          ? "INGESTING 30 FPS rPPG VIDEO" 
                          : "POSITION FACE IN OVAL",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (isScanning) ...[
                Text(
                  "Hold still: ${remainingSeconds}s remaining",
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

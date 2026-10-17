class RppgFrame {
  final double red;
  final double green;
  final double blue;
  final int timestampMs;

  RppgFrame({
    required this.red,
    required this.green,
    required this.blue,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'r': red,
      'g': green,
      'b': blue,
      't': timestampMs,
    };
  }
}

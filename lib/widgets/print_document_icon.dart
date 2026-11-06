import 'package:flutter/material.dart';

/// 아이콘 폰트 설치 상태와 관계없이 표시되는 프린터 아이콘입니다.
class PrintDocumentIcon extends StatelessWidget {
  const PrintDocumentIcon({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CustomPaint(painter: _PrinterPainter()),
      );
}

class _PrinterPainter extends CustomPainter {
  const _PrinterPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 20, size.height / 20);
    final paint = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(5, 7)
          ..lineTo(5, 1)
          ..lineTo(15, 1)
          ..lineTo(15, 7),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(5, 16)
          ..lineTo(2, 16)
          ..lineTo(2, 7)
          ..lineTo(18, 7)
          ..lineTo(18, 16)
          ..lineTo(15, 16),
        paint);
    canvas.drawRect(const Rect.fromLTRB(5, 12, 15, 19), paint);
    canvas.drawLine(const Offset(7, 15), const Offset(13, 15), paint);
    canvas.drawCircle(
        const Offset(15, 9.5), 0.8, Paint()..color = const Color(0xFF1565C0));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PrinterPainter oldDelegate) => false;
}

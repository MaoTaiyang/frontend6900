import 'package:flutter/material.dart';

class SkeletonOverlayPainter extends CustomPainter {
  final List<dynamic> skeletonData;
  final int frameIndex;
  final Size videoSize; // 新增参数
  final bool showCoords; // 是否显示坐标

  SkeletonOverlayPainter({
    required this.skeletonData,
    required this.frameIndex,
    required this.videoSize, // 新增构造函数参数
    this.showCoords = false,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (skeletonData.isEmpty || frameIndex >= skeletonData.length) return;
    // 设置透明背景
    Paint clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), clearPaint);

    final List<dynamic> keypoints = skeletonData[frameIndex];
    if (keypoints.length % 3 != 0) return; // 确保关键点数据有效

    // 计算屏幕缩放比例
    double xScale = size.width / videoSize.width;
    double yScale = size.height / videoSize.height;

    List<Offset> points = [];

    // 遍历关键点数据
    for (int i = 0; i < keypoints.length; i += 3) {
      double x = keypoints[i] * xScale;
      double y = keypoints[i + 1] * yScale;
      double confidence = (keypoints[i + 2] as num).toDouble();

      if (confidence > 0.5) {
        Offset point = Offset(x, y);
        points.add(point);

        // 绘制关键点
        canvas.drawCircle(point, 3, Paint()..color = Colors.red);

        // 绘制坐标文本
        if (showCoords) {
          TextSpan span = TextSpan(
            style: TextStyle(color: Colors.blue[800], fontSize: 12),
            text: "(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})",
          );
          TextPainter tp = TextPainter(
            text: span,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
          );
          tp.layout();
          tp.paint(canvas, point.translate(5, -10)); // 偏移文本位置
        }
      } else {
        points.add(Offset.zero); // 如果置信度低，标记为零点
      }
    }

    // 绘制骨架连接
    _drawLines(canvas, points);
  }

  void _drawLines(Canvas canvas, List<Offset> points) {
    final Paint linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2;

    final List<List<int>> connections = [
      [0, 1], [1, 2], [2, 3], [3, 4], // 上半身右侧
      [1, 5], [5, 6], [6, 7], // 上半身左侧
      [1, 8], [8, 9], [9, 10], // 右腿
      [1, 11], [11, 12], [12, 13], // 左腿
      [0, 14], [14, 16], // 右眼到右耳
      [0, 15], [15, 17], // 左眼到左耳
      [8, 11], // 骨盆连接
      [8, 24], [11, 24], [24, 1], // 骨盆中心与左右臀部及脖子的连接
      [20, 21], [22, 23], // 左右脚
      [10, 22], [13, 20] // 脚部连接
    ];

    for (var connection in connections) {
      if (connection[0] < points.length && connection[1] < points.length) {
        final start = points[connection[0]];
        final end = points[connection[1]];
        if (start != Offset.zero && end != Offset.zero) {
          canvas.drawLine(start, end, linePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;

  // @override
  // void paint(Canvas canvas, Size size) {
  //   if (skeletonData.isNotEmpty && frameIndex < skeletonData.length) {
  //     final List<dynamic> keypoints = skeletonData[frameIndex];

  //     if (keypoints.length % 3 == 0) {
  //       // 计算屏幕缩放比例
  //       double xScale = size.width / videoSize.width;
  //       double yScale = size.height / videoSize.height;
  //       print("尺寸尺寸xScale: $xScale, yScale: $yScale");

  //       for (int i = 0; i < keypoints.length; i += 3) {
  //         // 提取 x, y 坐标和置信度
  //         double x = keypoints[i] * xScale;
  //         double y = keypoints[i + 1] * yScale;
  //         double confidence = (keypoints[i + 2] as num).toDouble();
  //         print("关键点坐标: ($x, $y), 置信度: $confidence");
  //         if (confidence > 0.5) {
  //           // 计算缩放比例
  //           double xScale = size.width / videoSize.width; // 使用真实视频宽度
  //           double yScale = size.height / videoSize.height; // 使用真实视频高度
  //           double nx = x * xScale;
  //           double ny = y * yScale;
  //           // Draw keypoints
  //           canvas.drawCircle(Offset(nx, ny), 3, Paint()..color = Colors.red);

  //           // 如果需要显示坐标，绘制坐标文本
  //           if (showCoords) {
  //             TextSpan span = TextSpan(
  //               style: TextStyle(color: Colors.blue[800]),
  //               text: "($x, $y)",
  //             );
  //             TextPainter tp = TextPainter(
  //               text: span,
  //               textAlign: TextAlign.left,
  //               textDirection: TextDirection.ltr,
  //             );
  //             tp.layout();
  //             tp.paint(canvas, Offset(nx + 5, ny + 5));
  //           }
  //         }
  //       }
  //     }

  //     // 绘制关键点之间的连线
  //     _drawLines(canvas, keypoints.cast<double>(), size);
  //   }
  // }

  // void _drawLines(Canvas canvas, List<double> keypoints, Size size) {
  //   var paint = Paint()
  //     ..color = Colors.green
  //     ..strokeWidth = 2;

  //   final List<List<int>> connections = [
  //     [0, 1], [1, 2], [2, 3], [3, 4], // 上半身右侧
  //     [1, 5], [5, 6], [6, 7], // 上半身左侧
  //     [1, 8], [8, 9], [9, 10], // 右腿
  //     [1, 11], [11, 12], [12, 13], // 左腿
  //     [0, 14], [14, 16], // 右眼到右耳
  //     [0, 15], [15, 17], // 左眼到左耳
  //     [8, 11], // 骨盆连接
  //     [8, 24], [11, 24], [24, 1], // 骨盆中心与左右臀部及脖子的连接
  //     [20, 21], [22, 23], // 左右脚
  //     [10, 22], [13, 20] // 脚部连接
  //   ];

  //   for (var connection in connections) {
  //     if (connection[0] < points.length && connection[1] < points.length) {
  //       final start = points[connection[0]];
  //       final end = points[connection[1]];
  //       if (start != Offset.zero && end != Offset.zero) {
  //         canvas.drawLine(start, end, linePaint);
  //       }
  //     }
  //   }
  // }

  // @override
  // bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

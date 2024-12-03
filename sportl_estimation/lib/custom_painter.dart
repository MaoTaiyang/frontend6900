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
    if (skeletonData.isNotEmpty && frameIndex < skeletonData.length) {
      var frameData = skeletonData[frameIndex];
      var people = frameData['people'];

      for (var person in people) {
        var keypoints = person['pose_keypoints_2d'];
        for (int i = 0; i < keypoints.length; i += 3) {
          double x = keypoints[i];
          double y = keypoints[i + 1];
          double confidence = keypoints[i + 2];

          if (confidence > 0.5) {
            // 计算缩放比例
            double xScale = size.width / videoSize.width; // 使用真实视频宽度
            double yScale = size.height / videoSize.height; // 使用真实视频高度
            double nx = x * xScale;
            double ny = y * yScale;
            // Draw keypoints
            canvas.drawCircle(Offset(nx, ny), 3, Paint()..color = Colors.red);

            // Draw coordinates text if enabled
            if (showCoords) {
              TextSpan span = new TextSpan(
                  style: new TextStyle(color: Colors.blue[800]),
                  text: "($x,$y)");
              TextPainter tp = new TextPainter(
                  text: span,
                  textAlign: TextAlign.left,
                  textDirection: TextDirection.ltr);
              tp.layout();
              tp.paint(canvas, Offset(nx + 5, ny + 5));
            }
          }
        }

        // Draw lines between keypoints
        _drawLines(canvas, keypoints, size);
      }
    }
  }

  void _drawLines(Canvas canvas, List<double> keypoints, Size size) {
    var paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2;

    final List<List<int>> Connections = [
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

    for (var link in Connections) {
      int start = link[0] * 3;
      int end = link[1] * 3;
      if (keypoints[start + 2] > 0.5 && keypoints[end + 2] > 0.5) {
        double sx = keypoints[start] * size.width / videoSize.width;
        double sy = keypoints[start + 1] * size.height / videoSize.height;
        double ex = keypoints[end] * size.width / videoSize.width;
        double ey = keypoints[end + 1] * size.height / videoSize.height;
        canvas.drawLine(Offset(sx, sy), Offset(ex, ey), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

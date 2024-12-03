import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'custom_painter.dart';
import 'package:http/http.dart' as http;

class VideoWithOverlayPage extends StatefulWidget {
  final String videoUrl;
  final String jsonFolderPathUrl;

  const VideoWithOverlayPage({
    Key? key,
    required this.videoUrl,
    required this.jsonFolderPathUrl,
  }) : super(key: key);

  @override
  _VideoWithOverlayPageState createState() => _VideoWithOverlayPageState();
}

class _VideoWithOverlayPageState extends State<VideoWithOverlayPage>
    with WidgetsBindingObserver {
  late VideoPlayerController _videoController;
  late VideoPlayerController? _maskController = null;
  bool isGeneratingMask = false;
  bool showMask = true;
  double? videoAspectRatio; // 添加一个变量存储视频宽高比

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _checkAndGenerateMaskVideo();
    WidgetsBinding.instance.addObserver(this); // 添加生命周期监听
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.network(widget.videoUrl);
    await _videoController.initialize();
    videoAspectRatio = _videoController.value.aspectRatio; // 初始化宽高比
    setState(() {});
  }

  Future<void> _checkAndGenerateMaskVideo() async {
    final maskVideoPath = await _getMaskVideoPath(widget.videoUrl);

    if (await File(maskVideoPath).exists()) {
      _loadMaskVideo(maskVideoPath);
    } else {
      setState(() {
        isGeneratingMask = true;
      });
      await _generateMaskVideo(maskVideoPath);
      setState(() {
        isGeneratingMask = false;
      });
      _loadMaskVideo(maskVideoPath);
    }
  }

  Future<String> _getMaskVideoPath(String videoUrl) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = videoUrl.hashCode.toString();
    return "${directory.path}/${fileName}_mask.mp4";
  }

  Future<void> _generateMaskVideo(String outputPath) async {
    // Download skeleton data
    final skeletonData = await _downloadSkeletonData();
    if (skeletonData == null) return;

    // Generate frames and combine to a video
    final FlutterFFmpeg _flutterFFmpeg = FlutterFFmpeg();
    final directory = await getApplicationDocumentsDirectory();
    final framePaths = <String>[];

    for (int i = 0; i < skeletonData.length; i++) {
      // 检查视频尺寸是否有效
      if (_videoController.value.size == Size.zero) {
        throw Exception("视频尺寸不可用");
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // 创建 SkeletonOverlayPainter 实例
      final painter = SkeletonOverlayPainter(
        skeletonData: skeletonData,
        frameIndex: i,
        videoSize: _videoController.value.size, // 使用视频的尺寸
      );
      painter.paint(canvas, _videoController.value.size);
      final picture = recorder.endRecording();
      final img = await picture.toImage(
        _videoController.value.size.width.toInt(),
        _videoController.value.size.height.toInt(),
      );

      // 保存帧图像
      final framePath = "${directory.path}/frame_$i.png";
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final frameFile = File(framePath);
      await frameFile.writeAsBytes(byteData!.buffer.asUint8List());
      framePaths.add(framePath);
    }

    final framesInput = "${directory.path}/file_input.txt";
    await File(framesInput).writeAsString(
      framePaths.map((path) => "file '$path'").join('\n'),
    );

    await _flutterFFmpeg.execute(
      "-f concat -safe 0 -i $framesInput -r 30 -pix_fmt yuv420p $outputPath",
    );

    for (final framePath in framePaths) {
      File(framePath).deleteSync();
    }
  }

  Future<List<dynamic>?> _downloadSkeletonData() async {
    try {
      // 发起 HTTP 请求
      final response = await http.get(Uri.parse(widget.jsonFolderPathUrl));
      print("Skeleton Data Response: ${response.body}"); // 打印返回的数据

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("Loaded Skeleton Data: ${data['skeleton_data'] ?? []}");

        if (data['skeleton_data'] != null && data['skeleton_data'].isNotEmpty) {
          print("第一帧骨架数据: ${data['skeleton_data'][0]}");
          print("骨架数据总帧数: ${data['skeleton_data'].length}");
        } else {
          print("骨架数据为空");
        }

        return data['skeleton_data']; // 返回骨架数据
      } else {
        print(
            "Failed to load skeleton data. Status code: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("Error loading skeleton data: $e");
      return [];
    }
  }

  void _loadMaskVideo(String path) {
    _maskController = VideoPlayerController.file(File(path))
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 移除生命周期监听
    _videoController.dispose();
    _maskController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 应用进入后台时，暂停视频播放
      _videoController.pause();
      _maskController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      // 应用返回前台时，重新播放视频（根据需求，可省略）
      _videoController.play();
      _maskController?.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("视频与骨架蒙版"),
      ),
      body: Stack(
        children: [
          if (_videoController.value.isInitialized)
            // 使用 Container 让原视频填充父容器
            Container(
              width: double.infinity, // 确保容器填满父容器
              height: double.infinity,
              child: AspectRatio(
                aspectRatio: _videoController.value.aspectRatio,
                child: VideoPlayer(_videoController),
              ),
            ),
          if (showMask &&
              _maskController != null &&
              _maskController!.value.isInitialized)
            // 使用 Container 让蒙版视频也填充父容器
            Container(
              width: double.infinity, // 确保容器填满父容器
              height: double.infinity,
              child: AspectRatio(
                aspectRatio: _maskController!.value.aspectRatio,
                child: VideoPlayer(_maskController!),
              ),
            ),
          if (isGeneratingMask)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  const Text("骨架生成中，请等待..."),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _videoController.value.isInitialized &&
              !isGeneratingMask
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: Icon(_videoController.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow),
                  onPressed: () {
                    if (_videoController.value.isInitialized &&
                        _maskController?.value.isInitialized == true) {
                      // 确保两个控制器已初始化
                      if (_videoController.value.isPlaying) {
                        // 暂停两个视频
                        _videoController.pause();
                        _maskController?.pause();
                      } else {
                        // 播放两个视频
                        _videoController.play();
                        _maskController?.play();
                      }

                      // 确保两个视频的播放进度始终一致
                      _maskController?.seekTo(_videoController.value.position);
                    }
                  },
                ),
                DropdownButton<double>(
                  value: _videoController.value.playbackSpeed,
                  items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                      .map((speed) => DropdownMenuItem(
                            value: speed,
                            child: Text("${speed}x"),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      _videoController.setPlaybackSpeed(value); // 设置原视频播放速度
                      _maskController?.setPlaybackSpeed(value); // 设置蒙版视频播放速度
                      // 确保两个控制器已初始化
                      _videoController.setPlaybackSpeed(value);
                      _maskController?.setPlaybackSpeed(value);
                    }
                  },
                ),
                Switch(
                  value: showMask,
                  onChanged: (value) {
                    setState(() {
                      showMask = value;
                    });
                  },
                ),
              ],
            )
          : null,
    );
  }
}

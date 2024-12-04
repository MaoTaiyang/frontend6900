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
    super.key,
    required this.videoUrl,
    required this.jsonFolderPathUrl,
  });

  @override
  _VideoWithOverlayPageState createState() => _VideoWithOverlayPageState();
}

class _VideoWithOverlayPageState extends State<VideoWithOverlayPage>
    with WidgetsBindingObserver {
  late VideoPlayerController _videoController;
  VideoPlayerController? _maskController;
  late final String maskVideoPath;
  bool isGeneratingMask = false;
  bool showMask = true;
  bool isMaskVideoGenerated = false;
  double? videoAspectRatio; // 添加一个变量存储视频宽高比

  @override
  void initState() {
    super.initState();
    print("初始化视频控制器...");
    _initializeVideo().then((_) {
      print("视频控制器初始化完成");
      _getMaskVideoPath(widget.videoUrl).then((path) {
        if (mounted) {
          setState(() {
            maskVideoPath = path;
            print("maskVideoPath 初始化为: $maskVideoPath");
          });
        }
        _checkAndGenerateMaskVideo().then((_) {
          // 确保蒙版视频进度与原视频同步
          if (_maskController != null && _maskController!.value.isInitialized) {
            _maskController!.seekTo(_videoController.value.position);
            _maskController!
                .setPlaybackSpeed(_videoController.value.playbackSpeed);
          }
        });
      });
    });
    WidgetsBinding.instance.addObserver(this); // 添加生命周期监听
  }

  Future<String> _getMaskVideoPath(String videoUrl) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = videoUrl.hashCode.toString(); // 生成文件名
    return "${directory.path}/${fileName}_mask.mp4";
  }

  Future<void> _initializeVideo() async {
    print("初始化视频控制器...");
    print("视频 URL: ${widget.videoUrl}");

    try {
      _videoController = VideoPlayerController.network(widget.videoUrl);
      print("视频控制器哈希值（初始化阶段）: ${_videoController.hashCode}");

// 添加监听器以检测初始化状态的变化
      _videoController.addListener(() {
        if (_videoController.value.isInitialized &&
            _maskController?.value.isInitialized == true) {
          print("监听到视频控制器初始化完成");
          print("监听器中的视频宽度: ${_videoController.value.size.width}");
          print("监听器中的视频高度: ${_videoController.value.size.height}");
          final currentPosition = _videoController.value.position;
          if (!_videoController.value.isPlaying) {
            _maskController?.seekTo(currentPosition);
          }
          if (mounted) {
            setState(() {}); // 更新界面
          }
        }
      });

      await _videoController.initialize();

      // 分别获取视频的宽度和高度
      final double videoWidth = _videoController.value.size.width;
      final double videoHeight = _videoController.value.size.height;

      // 打印调试信息
      print("视频宽度1: $videoWidth");
      print("视频高度1: $videoHeight");

      if (videoWidth <= 0 || videoHeight <= 0) {
        print("警告：视频尺寸无效，宽: $videoWidth，高: $videoHeight");
        throw Exception("视频尺寸不可用，请检查视频路径或元数据加载是否成功");
      }
      videoAspectRatio = _videoController.value.aspectRatio;
      // 如果蒙版视频已初始化，提前同步播放速度和进度
      if (_maskController?.value.isInitialized == true &&
          _videoController.value.isInitialized) {
        _maskController!.setPlaybackSpeed(_videoController.value.playbackSpeed);
        _maskController!.seekTo(_videoController.value.position);
      }

      setState(() {}); // 更新 UI
    } catch (e) {
      print("视频初始化失败：$e");
      setState(() {
        isGeneratingMask = false; // 停止加载提示
      });
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

  Future<void> _generateMaskVideo(String outputPath) async {
    try {
      print("开始生成蒙版视频...");

      print("视频控制器哈希值（初始化阶段）: ${_videoController.hashCode}");
      print("当前视频宽度: ${_videoController.value.size.width}");
      print("当前视频高度: ${_videoController.value.size.height}");
      if (_maskController != null) {
        print("蒙版控制器是否初始化: ${_maskController!.value.isInitialized}");
      }
      if (!_videoController.value.isInitialized ||
          _videoController.value.size == Size.zero) {
        print("错误：视频未初始化或尺寸无效，无法生成蒙版");
        return;
      }
      // 创建状态文件
      final File incompleteFile = File(outputPath + '.incomplete');
      await incompleteFile.create(); // 创建标记文件

      // Download skeleton data
      final skeletonData = await _downloadSkeletonData();
      if (skeletonData == null) {
        incompleteFile.deleteSync(); // 如果数据无效，删除标记文件
        return;
      }

      // Generate frames and combine to a video
      final FlutterFFmpeg flutterFFmpeg = FlutterFFmpeg();
      final directory = await getApplicationDocumentsDirectory();
      final framePaths = <String>[];

      // 获取视频宽度和高度
      final double videoWidth = _videoController.value.size.width;
      final double videoHeight = _videoController.value.size.height;

      // 检查视频尺寸是否有效
      if (videoWidth <= 0 || videoHeight <= 0) {
        throw Exception("视频尺寸不可用，宽: $videoWidth，高: $videoHeight");
      }

      for (int i = 0; i < skeletonData.length; i++) {
        // 检查视频尺寸是否有效

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        // 创建 SkeletonOverlayPainter 实例
        final painter = SkeletonOverlayPainter(
          skeletonData: skeletonData,
          frameIndex: i,
          videoSize: Size(videoWidth, videoHeight), // 使用视频的尺寸
        );
        painter.paint(canvas, Size(videoWidth, videoHeight));
        final picture = recorder.endRecording();
        final img = await picture.toImage(
          videoWidth.toInt(),
          videoHeight.toInt(),
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

      await flutterFFmpeg
          .execute(
        "-f concat -safe 0 -i $framesInput -r 30 -pix_fmt yuva420p $outputPath",
      )
          .then((rc) {
        print("FFmpeg finished with return code $rc");
      }).catchError((e) {
        print("FFmpeg error: $e");
      });

      for (final framePath in framePaths) {
        final file = File(framePath);
        if (file.existsSync()) {
          file.deleteSync();
        } else {
          print("文件不存在，无法删除: $framePath");
        }
      }

      if (incompleteFile.existsSync()) {
        incompleteFile.deleteSync(); // 清理标记文件
        print("删除生成完成的标记文件: ${incompleteFile.path}");
      }
    } catch (e) {
      print("蒙版视频生成失败: $e");
      // 若生成失败，不删除标记文件
    }
  }

  Future<void> _loadMaskVideo(String path) async {
    final file = File(path);
    final fileSize = file.lengthSync();
    if (file.existsSync()) {
      if (fileSize > 1000) {
        print("蒙版视频文件存在，大小: $fileSize 字节，路径: $path");
        // 检查文件是否存在且大小合理
        if (_maskController == null || !_maskController!.value.isInitialized) {
          _maskController = VideoPlayerController.file(file);
          await _maskController!.initialize(); // 使用 await 等待完成
          // 同步播放速度和进度
          _maskController!
              .setPlaybackSpeed(_videoController.value.playbackSpeed);
          _maskController!.seekTo(_videoController.value.position);

          if (mounted) {
            setState(() {}); // 更新界面
          }
        }
      } else {
        print("文件大小无效: $fileSize 字节，路径: $path，删除文件");
        file.deleteSync(); // 删除不完整文件
      }
    } else {
      print("蒙版视频文件不存在: $path");
    }
  }

  @override
  void dispose() {
    // 检查是否有未完成的生成任务

    final File incompleteFile = File(maskVideoPath + '.incomplete');

    if (incompleteFile.existsSync()) {
      print("检测到未完成任务，清理文件: ${incompleteFile.path}");
      incompleteFile.deleteSync(); // 删除未完成标记文件

      final File incompleteVideoFile = File(maskVideoPath);
      if (incompleteVideoFile.existsSync()) {
        incompleteVideoFile.deleteSync(); // 删除未完成的视频文件
        print("清理未完成视频文件: ${incompleteVideoFile.path}");
      }
    }

    WidgetsBinding.instance.removeObserver(this);
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
      // 同步蒙版视频的播放进度
      _maskController?.seekTo(_videoController.value.position);
    }
  }

  Future<void> _checkAndGenerateMaskVideo() async {
    try {
      // 如果蒙版视频已经生成并加载过，直接返回
      if (isMaskVideoGenerated) {
        print("蒙版视频已生成并加载，无需重复生成");
        return;
      }

      // 获取蒙版视频路径
      final maskVideoPath = await _getMaskVideoPath(widget.videoUrl);
      final incompleteFile = File(maskVideoPath + '.incomplete');
      final maskFile = File(maskVideoPath);

      // 检查并删除未完成的标记文件
      if (incompleteFile.existsSync()) {
        print("发现未完成的生成任务: ${incompleteFile.path}");
        incompleteFile.deleteSync(); // 删除未完成标记文件

        if (maskFile.existsSync()) {
          maskFile.deleteSync(); // 删除不完整视频文件
          print("删除未完成的视频文件: ${maskFile.path}");
        }
      }

      // 检查蒙版视频是否存在且完整
      if (maskFile.existsSync()) {
        final fileSize = maskFile.lengthSync();
        if (fileSize > 100000) {
          // 根据实际蒙版视频文件大小调整阈值
          print("蒙版视频文件存在且完整，大小: $fileSize 字节");
          await _loadMaskVideo(maskVideoPath); // 加载已有蒙版视频
          setState(() {
            isMaskVideoGenerated = true; // 设置为已生成状态
          });
          return;
        } else {
          print("蒙版视频文件不完整，大小: $fileSize 字节，删除...");
          maskFile.deleteSync(); // 删除不完整文件
        }
      }

      // 更新状态为正在生成
      if (mounted) {
        setState(() {
          isGeneratingMask = true;
        });
      }

      // 检查视频控制器是否已初始化且尺寸有效
      if (!_videoController.value.isInitialized ||
          _videoController.value.size == Size.zero ||
          _videoController.value.size.width <= 0 ||
          _videoController.value.size.height <= 0) {
        print("错误：视频未正确初始化或尺寸无效，无法生成蒙版视频");
        if (mounted) {
          setState(() {
            isGeneratingMask = false; // 更新状态
          });
        }
        return;
      }

      // 调用生成蒙版视频的方法
      await _generateMaskVideo(maskVideoPath);

      // 更新状态为完成
      if (mounted) {
        setState(() {
          isGeneratingMask = false;
          isMaskVideoGenerated = true; // 更新为已生成状态
        });
      }
    } catch (e) {
      print("检查和生成蒙版视频时发生错误: $e");
      if (mounted) {
        setState(() {
          isGeneratingMask = false; // 确保状态回退
        });
      }
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
            SizedBox(
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
            SizedBox(
              width: double.infinity, // 确保容器填满父容器
              height: double.infinity,
              child: AspectRatio(
                aspectRatio: _maskController!.value.aspectRatio,
                child: VideoPlayer(_maskController!),
              ),
            ),
          if (isGeneratingMask)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text("骨架生成中，请等待..."),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar:
          _videoController.value.isInitialized && !isGeneratingMask
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
                            // 同步蒙版视频的进度到原视频
                            if (_maskController?.value.isInitialized == true) {
                              final position = _videoController.value.position;
                              _maskController?.seekTo(position);
                            }

                            // 播放两个视频
                            _videoController.play();
                            _maskController?.play();
                          }

                          // 切换播放/暂停状态后更新界面
                          setState(() {});
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
                          if (_videoController.value.isInitialized) {
                            _videoController.setPlaybackSpeed(value);
                          }
                          if (_maskController?.value.isInitialized == true) {
                            _maskController!.setPlaybackSpeed(value);
                          }
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:better_player/better_player.dart';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'custom_painter.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart'; // 用于 md5 加密
import 'package:permission_handler/permission_handler.dart';

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
  double? videoAspectRatio; // 存储原视频宽高比
  double? maskVideoAspectRatio; // 存储蒙版视频宽高比
  bool isPlaying = false; // 播放状态
  double sliderValue = 0.0; // 进度条的值
  bool isMaskTaskRunning = false; // 用于标记蒙版任务的运行状态
  final directory = "/data/data/com.example.sport_estimation";

  @override
  void initState() {
    super.initState();

    _initializeAsync(); // 调用异步方法
    WidgetsBinding.instance.addObserver(this); // 添加生命周期监听
  }

  Future<void> _initializeAsync() async {
// 初始化视频控制器并等待完成
    await _initializeVideo();

    if (!_videoController.value.isInitialized) {
      print("视频控制器初始化失败，停止后续逻辑");
      return;
    }
    print("视频控制器初始化完成");

    // // 检查并申请权限
    // await initializeApp();
    // if (!(await Permission.storage.isGranted) ||
    //     !(Platform.isAndroid &&
    //         await Permission.manageExternalStorage.isGranted)) {
    //   print("必要权限未授予，停止后续初始化流程");
    //   return; // 中断后续逻辑
    // }

    try {
      // 获取蒙版路径
      final path = await _getMaskVideoPath(widget.videoUrl);
      maskVideoPath = path;
      print("maskVideoPath 初始化为: $maskVideoPath");

      final maskFile = File(maskVideoPath);

      // 检查是否已有任务正在运行
      if (isMaskTaskRunning) {
        print("蒙版任务已在运行，跳过重复执行");
        return; // 如果任务已运行，直接退出
      }

      // 设置任务运行状态
      setState(() {
        isMaskTaskRunning = true;
      });

      try {
        if (maskFile.existsSync()) {
          print("蒙版视频已存在，加载蒙版视频");
          await _loadMaskVideo(maskVideoPath);
        } else {
          print("蒙版视频不存在，开始生成");
          await _generateMaskVideo(maskVideoPath);
          await _loadMaskVideo(maskVideoPath);
        }
      } catch (e) {
        print("蒙版任务失败：$e");
      } finally {
        // 重置任务运行状态
        setState(() {
          isMaskTaskRunning = false;
        });
      }
    } catch (e) {
      print("初始化失败：$e");
    }
  }

  Future<String> _getMaskVideoPath(String videoUrl) async {
    final directory = "/data/data/com.example.sport_estimation";
    final Directory dir = Directory(directory);

    print("存储目录路径: ${dir?.path}"); // 打印存储路径
    // 确保存储目录已存在
    if (!await dir.exists()) {
      print("存储目录不存在，开始创建...");
      await dir.create(recursive: true);
      print("存储目录已创建: ${dir.path}");
    } else {
      print("存储目录已存在: ${dir.path}");
    }

    // 使用 md5 将 videoUrl 转换为合法文件名
    final md5Hash = md5.convert(utf8.encode(videoUrl)).toString();
    // 生成文件路径
    final filePath = "${dir.path}/${md5Hash}_mask.webm";

    print("存储文件名已创建: ${filePath}");
    return filePath;
  }

//监听器
  void _addVideoControllerListener() {
    _videoController.addListener(() {
      // 检查视频是否已初始化
      if (_videoController.value.isInitialized) {
        final currentPosition = _videoController.value.position;

        // 同步蒙版视频的播放和进度
        if (_maskController != null && _maskController!.value.isInitialized) {
          if (_videoController.value.isPlaying) {
            // 确保蒙版视频与原视频同步播放
            if (!_maskController!.value.isPlaying) {
              _maskController!.play();
            }
            _maskController!.seekTo(currentPosition);
          } else {
            // 确保蒙版视频与原视频同步暂停
            if (_maskController!.value.isPlaying) {
              _maskController!.pause();
            }
          }

          // 同步蒙版视频的播放进度
          _maskController!.seekTo(currentPosition);
        }

        // 更新UI，包括进度条和播放按钮状态
        if (mounted) {
          setState(() {
            // 更新进度条位置
            sliderValue = currentPosition.inSeconds.toDouble();

            // 更新播放/暂停按钮状态
            isPlaying = _videoController.value.isPlaying;
          });
        }
      }
    });
  }

  Future<void> _initializeVideo() async {
    print("初始化视频控制器...");
    print("视频 URL: ${widget.videoUrl}");

    try {
      _videoController = VideoPlayerController.network(widget.videoUrl);
      print("视频控制器哈希值（初始化阶段）: ${_videoController.hashCode}");

      // 等待视频初始化完成
      await _videoController.initialize();

      // 分别获取视频的宽度和高度
      final double videoWidth = _videoController.value.size.width;
      final double videoHeight = _videoController.value.size.height;

      // 打印调试信息
      print("视频宽度1: $videoWidth");
      print("视频高度1: $videoHeight");

      // 检查视频尺寸
      if (videoWidth <= 0 || videoHeight <= 0) {
        print("警告：视频尺寸无效，宽: $videoWidth，高: $videoHeight");
        throw Exception("视频尺寸不可用，请检查视频路径或元数据加载是否成功");
      }

      // 添加监听器
      _addVideoControllerListener();

      print("视频宽度: $videoWidth, 高度: $videoHeight");

      print("更新视频宽度和高度到状态: 宽: $videoWidth, 高: $videoHeight");

      setState(() {}); // 更新 UI
    } catch (e, stackTrace) {
      print("视频初始化失败：$e");
      print("错误堆栈：$stackTrace");
      setState(() {
        isGeneratingMask = false; // 停止加载提示
      });
    }
  }

//骨架数据下载
  Future<List<dynamic>?> _downloadSkeletonData() async {
    try {
      // 发起 HTTP 请求
      print("获取骨架信息。");
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

      if (!_videoController.value.isInitialized ||
          _videoController.value.size.width <= 0 ||
          _videoController.value.size.height <= 0) {
        print("错误：视频未初始化或尺寸无效，无法生成蒙版");
        return;
      }

      // 创建状态文件
      final File incompleteFile = File(outputPath + '.incomplete');
      print("标记文件地址: $incompleteFile");

      final Directory parentDirectory = incompleteFile.parent;
      print("Incomplete file path: ${incompleteFile.path}");
      print("Parent directory path: ${parentDirectory.path}");

      // 确保父目录已存在
      if (!await parentDirectory.exists()) {
        print("父目录不存在，开始创建...${parentDirectory.path}");
        await parentDirectory.create(recursive: true).then((_) async {
          print("父目录已创建: ${parentDirectory.path}");

          print("创建标记文件...");
          await incompleteFile.create(); // 创建标记文件
          print("标记文件地址: ${incompleteFile.path}");

          // 下载骨架数据
          final skeletonData = await _downloadSkeletonData();
          if (skeletonData == null || skeletonData.isEmpty) {
            print("骨架数据无效，删除标记文件并终止生成任务");
            await incompleteFile.delete(); // 删除标记文件
            return;
          }

          // 获取视频宽度和高度
          final double videoWidth = _videoController.value.size.width;
          final double videoHeight = _videoController.value.size.height;

          // 检查视频尺寸是否有效
          if (videoWidth <= 0 || videoHeight <= 0) {
            throw Exception("视频尺寸不可用，宽: $videoWidth，高: $videoHeight");
          }

          // 创建帧并合成为视频
          final FlutterFFmpeg flutterFFmpeg = FlutterFFmpeg();
          //final directory = await getApplicationDocumentsDirectory();
          final directory = "/data/data/com.example.sport_estimation";
          final framePaths = <String>[];

          for (int i = 0; i < skeletonData.length; i++) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);

            // 创建 SkeletonOverlayPainter 实例
            final painter = SkeletonOverlayPainter(
              skeletonData: skeletonData,
              frameIndex: i,
              videoSize: Size(videoWidth, videoHeight),
            );
            painter.paint(canvas, Size(videoWidth, videoHeight));
            final picture = recorder.endRecording();
            final img = await picture.toImage(
              videoWidth.toInt(),
              videoHeight.toInt(),
            );

            // 保存帧图像
            final framePath = "${directory}/frame_$i.png";
            final byteData =
                await img.toByteData(format: ui.ImageByteFormat.png);
            final frameFile = File(framePath);
            await frameFile.writeAsBytes(byteData!.buffer.asUint8List());
            framePaths.add(framePath);
          }

          final framesInput = "${directory}/file_input.txt";
          await File(framesInput).writeAsString(
            framePaths.map((path) => "file '$path'").join('\n'),
          );

          await flutterFFmpeg
              .execute(
            "-f concat -safe 0 -i $framesInput -r 30 -pix_fmt yuva420p $outputPath",
          )
              .then((rc) {
            print("FFmpeg finished with return code $rc");
            print("蒙版视频生成成功，存储路径: $outputPath");
          }).catchError((e) {
            print("FFmpeg error: $e");
          });

          // 删除临时帧文件
          for (final framePath in framePaths) {
            final file = File(framePath);
            if (file.existsSync()) {
              file.deleteSync();
            } else {
              print("文件不存在，无法删除: $framePath");
            }
          }

          // 删除标记文件
          if (incompleteFile.existsSync()) {
            await incompleteFile.delete();
            print("删除生成完成的标记文件: ${incompleteFile.path}");
          }
        });
      } else {
        print("父目录已存在: ${parentDirectory.path}");
        // 创建标记文件
        print("创建标记文件...");
        await incompleteFile.create();
        print("标记文件地址: ${incompleteFile.path}");

        // 下载骨架数据
        final skeletonData = await _downloadSkeletonData();
        if (skeletonData == null || skeletonData.isEmpty) {
          print("骨架数据无效，删除标记文件并终止生成任务");
          await incompleteFile.delete(); // 删除标记文件
          return;
        }

        // 获取视频宽度和高度
        final double videoWidth = _videoController.value.size.width;
        final double videoHeight = _videoController.value.size.height;

        // 检查视频尺寸是否有效
        if (videoWidth <= 0 || videoHeight <= 0) {
          throw Exception("视频尺寸不可用，宽: $videoWidth，高: $videoHeight");
        }

        // 创建帧并合成为视频
        final FlutterFFmpeg flutterFFmpeg = FlutterFFmpeg();
        //final directory = await getApplicationDocumentsDirectory();
        final directory = "/data/data/com.example.sport_estimation";
        final framePaths = <String>[];

        for (int i = 0; i < skeletonData.length; i++) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);

          // 创建 SkeletonOverlayPainter 实例
          final painter = SkeletonOverlayPainter(
            skeletonData: skeletonData,
            frameIndex: i,
            videoSize: Size(videoWidth, videoHeight),
          );
          painter.paint(canvas, Size(videoWidth, videoHeight));
          final picture = recorder.endRecording();
          final img = await picture.toImage(
            videoWidth.toInt(),
            videoHeight.toInt(),
          );

          // 保存帧图像
          final framePath = "${directory}/frame_$i.png";
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          final frameFile = File(framePath);
          await frameFile.writeAsBytes(byteData!.buffer.asUint8List());
          framePaths.add(framePath);
        }

        final framesInput = "${directory}/file_input.txt";
        await File(framesInput).writeAsString(
          framePaths.map((path) => "file '$path'").join('\n'),
        );

        await flutterFFmpeg
            .execute(
          "-f concat -safe 0 -i $framesInput -r 30 -pix_fmt yuva420p $outputPath",
        )
            .then((rc) {
          print("FFmpeg finished with return code $rc");
          print("蒙版视频生成成功，存储路径: $outputPath");
        }).catchError((e) {
          print("FFmpeg error: $e");
        });

        // 删除临时帧文件
        for (final framePath in framePaths) {
          final file = File(framePath);
          if (file.existsSync()) {
            file.deleteSync();
          } else {
            print("文件不存在，无法删除: $framePath");
          }
        }
        print("删除临时帧文件");
        // 删除标记文件
        if (incompleteFile.existsSync()) {
          await incompleteFile.delete();
          print("删除生成完成的标记文件: ${incompleteFile.path}");
        }
      }
    } catch (e) {
      print("蒙版视频生成失败: $e");
      // 若生成失败，不删除标记文件
    }
  }

  Future<void> _loadMaskVideo(String path) async {
    final file = File(path);
    final incompleteFile = File(path + '.incomplete'); // 生成标记文件路径
    if (file.existsSync() && !incompleteFile.existsSync()) {
      print("蒙版视频文件已生成完成，路径1: $path");
      // 初始化蒙版视频控制器
      if (_maskController == null || !_maskController!.value.isInitialized) {
        _maskController = VideoPlayerController.file(file);
        await _maskController!.initialize(); // 初始化控制器
        // 确保蒙版视频控制器也有监听器
        _addVideoControllerListener();

        if (mounted) {
          setState(() {}); // 更新界面
        }
      }
    } else {
      // 标记文件存在或文件不存在，表示视频未生成完成
      if (!file.existsSync()) {
        print("蒙版视频文件不存在: $path");
      } else if (incompleteFile.existsSync()) {
        print("检测到未完成的蒙版视频任务，路径: $path");
      }
    }
  }

  @override
  void dispose() {
    // 检查是否有未完成的生成任务

    final File incompleteFile = File(maskVideoPath + '.incomplete');

    if (incompleteFile.existsSync()) {
      print("检测到未完成任务，标记文件路径: ${incompleteFile.path}");

      final File incompleteVideoFile = File(maskVideoPath);
      if (incompleteVideoFile.existsSync()) {
        incompleteVideoFile.deleteSync(); // 删除未完成的视频文件
        print("清理未完成视频文件: ${incompleteVideoFile.path}");
      }

      // 删除标记文件
      incompleteFile.deleteSync();
      print("清理未完成标记文件: ${incompleteFile.path}");
    }

    WidgetsBinding.instance.removeObserver(this);
    _videoController.dispose();
    _maskController?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
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
      bottomNavigationBar: _videoController.value.isInitialized &&
              !isGeneratingMask
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：进度条和时间显示
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 显示当前时间
                    Text(
                      _formatDuration(_videoController.value.position),
                      style: TextStyle(fontSize: 12),
                    ),
                    // 进度条
                    Expanded(
                      child: Slider(
                        value: sliderValue, // 从监听器同步的进度条值
                        max: _videoController.value.duration.inSeconds
                            .toDouble(),
                        onChanged: (value) {
                          setState(() {
                            sliderValue = value; // 实时更新进度条值
                          });
                        },
                        onChangeEnd: (value) {
                          // 滑动结束时更新视频进度
                          final newDuration = Duration(seconds: value.toInt());
                          _videoController.seekTo(newDuration);
                        },
                      ),
                    ),
                    // 显示总时长
                    Text(
                      _formatDuration(_videoController.value.duration),
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                // 第二行：播放按钮、倍速选择和蒙版开关
                Row(
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
                ),
              ],
            )
          : null,
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart';
import 'package:camera/camera.dart';

import 'scanner_utils.dart';
import 'detector_painters.dart';

typedef void TextDetected(String number);
typedef bool CheckCondition(String word);

class TicketDetector extends StatefulWidget {
  const TicketDetector({
    Key key,
    this.onDetected,
    this.condition,
    this.topLimit,
    this.detectorHeight,
  }) : super(key: key);

  final TextDetected onDetected;
  final CheckCondition condition;
  final double topLimit;
  final double detectorHeight;

  @override
  _TicketDetectorState createState() => _TicketDetectorState();
}

class _TicketDetectorState extends State<TicketDetector> {
  final _recognizer = FirebaseVision.instance.textRecognizer();
  VisionText _scanResults;
  CameraController _camera;
  Detector _currentDetector = Detector.text;
  bool _isDetecting = false;
  CameraLensDirection _direction = CameraLensDirection.back;
  Size _screenSize;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() async {
    final CameraDescription description =
        await ScannerUtils.getCamera(_direction);

    _camera = CameraController(
      description,
      defaultTargetPlatform == TargetPlatform.iOS
          ? ResolutionPreset.medium
          : ResolutionPreset.medium,
    );
    await _camera.initialize();

    _camera.startImageStream((CameraImage image) {
      if (_isDetecting) return;

      _isDetecting = true;

      ScannerUtils.detect(
        image: image,
        detectInImage: _recognizer.processImage,
        imageRotation: description.sensorOrientation,
      ).then(
        (dynamic results) {
          if (_currentDetector == null || results == null) return;
          if (results is VisionText) {
            final handled = handleScannerResults(results);
            if (handled) return;
            setState(() {
              _scanResults = results;
            });
          }
        },
      ).whenComplete(() => _isDetecting = false);
    });
  }

  Widget _buildResults() {
    const Text noResultsText = Text('No results!');

    if (_scanResults == null ||
        _camera == null ||
        !_camera.value.isInitialized) {
      return noResultsText;
    }

    CustomPainter painter;

    final Size imageSize = Size(
      _camera.value.previewSize.height,
      _camera.value.previewSize.width,
    );

    painter = TextDetectorPainter(imageSize, _scanResults);

    return CustomPaint(
      painter: painter,
    );
  }

  Widget _buildImage() {
    return WillPopScope(
      onWillPop: () async {
        await _camera.dispose().then((_) {
          _recognizer.close();
        });
        return true;
      },
      child: Container(
        child: _camera == null
            ? const Center(
                child: Text(
                  'Initializing Camera...',
                  style: TextStyle(
                    fontSize: 20.0,
                    color: Colors.white,
                  ),
                ),
              )
            : AspectRatio(
                aspectRatio: _camera.value.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CameraPreview(_camera),
                    // _buildResults(),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _screenSize = MediaQuery.of(context).size;
    return _buildImage();
  }

  @override
  void dispose() {
    _camera.dispose().then((_) {
      _recognizer.close();
    });

    _currentDetector = null;
    super.dispose();
  }

  bool handleScannerResults(VisionText results) {
    try {
      final _filteredScanRresults =
          results.blocks.where((b) => textWithinBounds(b)).toList();
      if (_filteredScanRresults != null && _filteredScanRresults.length > 0) {
        for (var text in _filteredScanRresults) {
          final words = text.lines;
          for (var line in words) {
            for (var word in line.text.split(' ')) {
              final correct = widget.condition(word);

              if (correct) {
                final result = word.toUpperCase();
                print(result);
                setState(() {
                  widget.onDetected(result);
                });
                return true;
              }
            }
          }
        }
      }
      print('No results');
    } catch (e) {
      // print(e);
    }
    return false;
  }

  bool textWithinBounds(TextBlock b) {
    final Size imageSize = Size(
      _camera.value.previewSize.height,
      _camera.value.previewSize.width,
    );
    final double scaleY = imageSize.height / _screenSize.height;
    print(scaleY);
    for (var l in b.lines) {
      for (var e in l.elements) {
        print(
            '${e.text} ${e.boundingBox.top}/${widget.topLimit + kToolbarHeight} ${e.boundingBox.bottom}/${widget.topLimit + widget.detectorHeight + kToolbarHeight}');

        final result =
            e.boundingBox.top > (widget.topLimit + kToolbarHeight) * scaleY &&
                e.boundingBox.bottom <
                    (widget.topLimit + widget.detectorHeight + kToolbarHeight) *
                        scaleY;

        if (result == true) {
          print('TRUE ${e.text}');
          return true;
        }
      }
    }

    return false;
  }
}

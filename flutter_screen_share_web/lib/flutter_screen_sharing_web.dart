import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:screen_share_platform_interface/flutter_screen_recording_platform_interface.dart';

class WebFlutterScreenRecording extends FlutterScreenSharingPlatform {
  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  web.Blob? _recordedBlob;
  String? _fileName;
  String? _mimeType;

  static void registerWith(Registrar registrar) {
    FlutterScreenSharingPlatform.instance = WebFlutterScreenRecording();
  }

  @override
  Future<bool> startRecordScreen(
    String name, {
    String notificationTitle = "",
    String notificationMessage = "",
  }) async {
    return _startRecording(name, recordAudio: false);
  }

  @override
  Future<bool> startRecordScreenAndAudio(
    String name, {
    String notificationTitle = "",
    String notificationMessage = "",
  }) async {
    return _startRecording(name, recordAudio: true);
  }

  Future<bool> _startRecording(String name, {required bool recordAudio}) async {
    try {
      _fileName = name;

      final constraints = web.DisplayMediaStreamOptions(
        video: web.DisplayMediaStreamOptions(),
        audio: recordAudio.toJS,
      );

      _stream = await web.window.navigator.mediaDevices
          .getDisplayMedia(constraints)
          .toDart;

      // ---- Add microphone audio if needed ----
      if (recordAudio) {
        final audioStream = await web.window.navigator.mediaDevices
            .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
            .toDart;
        final audioTrack = audioStream.getAudioTracks()[0];
        _stream!.addTrack(audioTrack);
      }

      // ---- Detect supported MIME type ----
      if (web.MediaRecorder.isTypeSupported("video/webm;codecs=vp9")) {
        _mimeType = "video/webm;codecs=vp9,opus";
      } else if (web.MediaRecorder.isTypeSupported("video/webm")) {
        _mimeType = "video/webm";
      } else {
        _mimeType = "video/webm";
      }

      final options = web.MediaRecorderOptions(mimeType: _mimeType!);

      _recorder = web.MediaRecorder(_stream!, options);

      // ---- Collect recorded chunks ----
      _recorder!.ondataavailable =
          (event) {
                final blobEvent = event as web.BlobEvent;
                _recordedBlob = blobEvent.data;
              }
              as web.EventHandler?;

      // ---- Stop recording if user stops screen ----
      _stream!.getVideoTracks()[0].onended =
          (_) {
                stopRecordScreen;
              }
              as web.EventHandler?;

      _recorder!.start();

      return true;
    } catch (e) {
      print("Error starting screen recording: $e");
      return false;
    }
  }

  @override
  Future<String> get stopRecordScreen async {
    final completer = Completer<String>();

    if (_recorder == null) {
      completer.completeError("No active recording");
      return completer.future;
    }

    _recorder!.onstop =
        (_) {
              final blob = _recordedBlob!;
              final url = web.URL.createObjectURL(blob);
              final a =
                  web.document.createElement("a") as web.HTMLAnchorElement;

              a.href = url;
              a.download = _fileName!;
              a.style.display = "none";
              web.document.body!.appendChild(a);
              a.click();
              web.URL.revokeObjectURL(url);

              // Stop all tracks
              final tracks = _stream?.getTracks().toDart;
              if (tracks != null) {
                for (final track in tracks) {
                  (track).stop();
                }
              }

              _stream = null;
              _recorder = null;
              _recordedBlob = null;

              completer.complete(_fileName!);
            }
            as web.EventHandler?;

    _recorder!.stop();

    return completer.future;
  }
}

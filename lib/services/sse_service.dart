import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/trace_event.dart';

/// SSE (Server-Sent Events) client for real-time trace streaming (FR-5.2).
class SseService {
  http.Client? _client;
  StreamController<TraceEvent>? _controller;
  bool _isDone = false;

  /// Open an SSE connection and return a stream of TraceEvents.
  Stream<TraceEvent> connect(String runId) {
    _isDone = false;
    
    // If the previous controller is still open, close it cleanly
    if (_controller != null && !_controller!.isClosed) {
      _controller!.close();
    }
    // Create a fresh controller for this connection
    _controller = StreamController<TraceEvent>.broadcast();
    _client = http.Client();

    _startListening(runId);

    return _controller!.stream;
  }

  Future<void> _startListening(String runId) async {
    try {
      final request = http.Request('GET', Uri.parse(ApiConfig.runEvents(runId)));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request);
      final stream = response.stream.transform(utf8.decoder);

      String buffer = '';

      await for (final chunk in stream) {
        buffer += chunk;

        // Parse SSE frames
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final frame = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);

          for (final line in frame.split('\n')) {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6);
              try {
                final json = jsonDecode(jsonStr) as Map<String, dynamic>;
                _controller?.add(TraceEvent.fromJson(json));
              } catch (_) {}
            } else if (line.startsWith('event: done')) {
              _isDone = true;
              if (_controller != null && !_controller!.isClosed) _controller!.close();
              return;
            }
          }
        }
      }
    } catch (e) {
      if (_controller != null && !_controller!.isClosed) _controller!.addError(e);
    } finally {
      if (!_isDone && _controller != null && !_controller!.isClosed) _controller!.close();
    }
  }

  bool get isDone => _isDone;

  void disconnect() {
    _client?.close();
    if (!(_controller?.isClosed ?? true)) {
      _controller?.close();
    }
  }
}

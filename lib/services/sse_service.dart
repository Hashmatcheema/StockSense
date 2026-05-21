import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/trace_event.dart';

/// SSE (Server-Sent Events) client for real-time trace streaming (FR-5.2).
class SseService {
  http.Client? _client;
  StreamController<TraceEvent>? _controller;
  StreamSubscription<String>? _httpSub;
  bool _isDone = false;
  bool _disposed = false;

  /// Open an SSE connection and return a stream of TraceEvents.
  Stream<TraceEvent> connect(String runId) {
    // Tear down any prior connection cleanly before starting a new one.
    disconnect();

    _isDone = false;
    _disposed = false;
    _client = http.Client();
    _controller = StreamController<TraceEvent>(
      onCancel: disconnect,
    );

    _startListening(runId);
    return _controller!.stream;
  }

  Future<void> _startListening(String runId) async {
    final client = _client;
    final controller = _controller;
    if (client == null || controller == null) return;

    try {
      final request = http.Request('GET', Uri.parse(ApiConfig.runEvents(runId)));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';
      final apiKey = ApiConfig.apiKey;
      if (apiKey.isNotEmpty) request.headers['X-API-Key'] = apiKey;

      final response = await client.send(request);
      if (_disposed) return;

      String buffer = '';
      // Cap buffer to protect against runaway streams.
      const maxBuffer = 1024 * 1024; // 1 MB

      _httpSub = response.stream.transform(utf8.decoder).listen(
        (chunk) {
          if (_disposed) return;
          buffer += chunk;
          if (buffer.length > maxBuffer) {
            // Trim at a \n\n frame boundary to avoid splitting a partial SSE frame.
            final cutAt = buffer.lastIndexOf('\n\n', buffer.length - maxBuffer);
            buffer = cutAt >= 0
                ? buffer.substring(cutAt + 2)
                : buffer.substring(buffer.length - maxBuffer);
          }

          while (buffer.contains('\n\n')) {
            final idx = buffer.indexOf('\n\n');
            final frame = buffer.substring(0, idx);
            buffer = buffer.substring(idx + 2);

            for (final line in frame.split('\n')) {
              if (line.startsWith('data: ')) {
                final jsonStr = line.substring(6);
                try {
                  final json = jsonDecode(jsonStr) as Map<String, dynamic>;
                  if (!controller.isClosed) {
                    controller.add(TraceEvent.fromJson(json));
                  }
                } catch (_) {}
              } else if (line.startsWith('event: done')) {
                _isDone = true;
                disconnect();
                return;
              }
            }
          }
        },
        onError: (e) {
          if (!controller.isClosed) controller.addError(e);
          disconnect();
        },
        onDone: () => disconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      if (!controller.isClosed) controller.addError(e);
      disconnect();
    }
  }

  bool get isDone => _isDone;

  /// Idempotent teardown. Safe to call multiple times.
  void disconnect() {
    if (_disposed) return;
    _disposed = true;
    _httpSub?.cancel();
    _httpSub = null;
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) c.close();
    _client?.close();
    _client = null;
  }
}

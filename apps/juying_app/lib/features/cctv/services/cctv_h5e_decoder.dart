import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Processes one complete H5E MPEG-TS segment off the UI isolate, without
/// transcoding. Each call owns its buffer and native decoder state for seeking.
Future<Uint8List> decodeCctvH5eSegment(Uint8List input) =>
    Isolate.run(() => _decode(input));

Uint8List _decode(Uint8List input) {
  if (!Platform.isWindows) throw UnsupportedError('H5E requires Windows');
  final library = DynamicLibrary.open(
    '${File(Platform.resolvedExecutable).parent.path}/juying_cctv_h5e.dll',
  );
  final allocate = library.lookupFunction<Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)>('juying_h5e_alloc');
  final release = library.lookupFunction<Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)>('juying_h5e_free');
  final decode = library.lookupFunction<Int32 Function(Pointer<Uint8>, IntPtr),
      int Function(Pointer<Uint8>, int)>('juying_h5e_decode');
  final buffer = allocate(input.length);
  if (buffer == nullptr) throw StateError('H5E buffer allocation failed');
  try {
    buffer.asTypedList(input.length).setAll(0, input);
    final result = decode(buffer, input.length);
    if (result != 0) throw FormatException('Unsupported H5E segment ($result)');
    return Uint8List.fromList(buffer.asTypedList(input.length));
  } finally {
    release(buffer);
  }
}

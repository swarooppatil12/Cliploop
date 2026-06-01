import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// Native source-separation API (sherpa-onnx C API, linked via sherpa_onnx_ios).

final class SherpaOnnxOfflineSourceSeparationSpleeterModelConfig
    extends Struct {
  external Pointer<Utf8> vocals;
  external Pointer<Utf8> accompaniment;
}

final class SherpaOnnxOfflineSourceSeparationUvrModelConfig extends Struct {
  external Pointer<Utf8> model;
}

final class SherpaOnnxOfflineSourceSeparationModelConfig extends Struct {
  external SherpaOnnxOfflineSourceSeparationSpleeterModelConfig spleeter;
  external SherpaOnnxOfflineSourceSeparationUvrModelConfig uvr;

  @Int32()
  external int numThreads;

  @Int32()
  external int debug;

  external Pointer<Utf8> provider;
}

final class SherpaOnnxOfflineSourceSeparationConfig extends Struct {
  external SherpaOnnxOfflineSourceSeparationModelConfig model;
}

final class SherpaOnnxOfflineSourceSeparation extends Opaque {}

final class SherpaOnnxSourceSeparationStem extends Struct {
  external Pointer<Pointer<Float>> samples;

  @Int32()
  external int num_channels;

  @Int32()
  external int n;
}

final class SherpaOnnxSourceSeparationOutput extends Struct {
  external Pointer<SherpaOnnxSourceSeparationStem> stems;

  @Int32()
  external int numStems;

  @Int32()
  external int sampleRate;
}

typedef _CreateNative = Pointer<SherpaOnnxOfflineSourceSeparation> Function(
  Pointer<SherpaOnnxOfflineSourceSeparationConfig>,
);
typedef _Create = Pointer<SherpaOnnxOfflineSourceSeparation> Function(
  Pointer<SherpaOnnxOfflineSourceSeparationConfig>,
);

typedef _DestroyNative = Void Function(
  Pointer<SherpaOnnxOfflineSourceSeparation>,
);
typedef _Destroy = void Function(Pointer<SherpaOnnxOfflineSourceSeparation>);

typedef _GetSampleRateNative = Int32 Function(
  Pointer<SherpaOnnxOfflineSourceSeparation>,
);
typedef _GetSampleRate = int Function(
  Pointer<SherpaOnnxOfflineSourceSeparation>,
);

typedef _GetNumStemsNative = Int32 Function(
  Pointer<SherpaOnnxOfflineSourceSeparation>,
);
typedef _GetNumStems = int Function(Pointer<SherpaOnnxOfflineSourceSeparation>);

typedef _ProcessNative = Pointer<SherpaOnnxSourceSeparationOutput> Function(
  Pointer<SherpaOnnxOfflineSourceSeparation>,
  Pointer<Pointer<Float>>,
  Int32,
  Int32,
  Int32,
);
typedef _Process = Pointer<SherpaOnnxSourceSeparationOutput> Function(
  Pointer<SherpaOnnxOfflineSourceSeparation>,
  Pointer<Pointer<Float>>,
  int,
  int,
  int,
);

typedef _DestroyOutputNative = Void Function(
  Pointer<SherpaOnnxSourceSeparationOutput>,
);
typedef _DestroyOutput = void Function(
  Pointer<SherpaOnnxSourceSeparationOutput>,
);

class SherpaSourceSeparationBindings {
  SherpaSourceSeparationBindings._();

  static SherpaSourceSeparationBindings? _instance;

  static SherpaSourceSeparationBindings get instance {
    _instance ??= SherpaSourceSeparationBindings._();
    return _instance!;
  }

  late final _Create create;
  late final _Destroy destroy;
  late final _GetSampleRate getSampleRate;
  late final _GetNumStems getNumStems;
  late final _Process process;
  late final _DestroyOutput destroyOutput;

  bool _initialized = false;

  void ensureInitialized() {
    if (_initialized) {
      return;
    }

    final DynamicLibrary lib;
    if (Platform.isIOS) {
      lib = DynamicLibrary.open('sherpa_onnx.framework/sherpa_onnx');
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open('libsherpa-onnx-c-api.so');
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.open('libsherpa-onnx-c-api.dylib');
    } else {
      lib = DynamicLibrary.process();
    }

    create = lib
        .lookup<NativeFunction<_CreateNative>>(
          'SherpaOnnxCreateOfflineSourceSeparation',
        )
        .asFunction();
    destroy = lib
        .lookup<NativeFunction<_DestroyNative>>(
          'SherpaOnnxDestroyOfflineSourceSeparation',
        )
        .asFunction();
    getSampleRate = lib
        .lookup<NativeFunction<_GetSampleRateNative>>(
          'SherpaOnnxOfflineSourceSeparationGetOutputSampleRate',
        )
        .asFunction();
    getNumStems = lib
        .lookup<NativeFunction<_GetNumStemsNative>>(
          'SherpaOnnxOfflineSourceSeparationGetNumberOfStems',
        )
        .asFunction();
    process = lib
        .lookup<NativeFunction<_ProcessNative>>(
          'SherpaOnnxOfflineSourceSeparationProcess',
        )
        .asFunction();
    destroyOutput = lib
        .lookup<NativeFunction<_DestroyOutputNative>>(
          'SherpaOnnxDestroySourceSeparationOutput',
        )
        .asFunction();

    _initialized = true;
  }
}

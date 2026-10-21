import 'dart:async';

import 'package:sandhai/core/location/location_service.dart';
import 'package:sandhai/core/location/nearby_geometry.dart';
import 'package:sandhai/core/location/store_location.dart';
import 'package:sandhai/data/nearby_query_source.dart';

class QueryProbe {
  QueryProbe(this.bound);
  final GeohashBound bound;
  late final stream = StreamController<NearbyChanges>(
    sync: true,
    onListen: () => active = true,
    onCancel: () => active = false,
  );
  bool active = false;
  void Function(NearbyChanges)? staleCallback;
  Stream<NearbyChanges> get events =>
      CapturedStream(stream.stream, (callback) => staleCallback = callback);
  void add(List<NearbyDocument> docs, [List<String> removed = const []]) =>
      stream.add(NearbyChanges(docs, removed));
}

/// Deliberately permits calling the saved callback after cancellation so tests
/// prove generation/disposal guards, rather than relying on StreamController.
class CapturedStream<T> extends Stream<T> {
  CapturedStream(this.source, this.capture);
  final Stream<T> source;
  final void Function(void Function(T)?) capture;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    capture(onData);
    return source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class TestNearbySource implements NearbyQuerySource {
  final probes = <QueryProbe>[];
  final vendorStreams = <String, StreamController<Map<String, dynamic>?>>{};
  int get active => probes.where((p) => p.active).length;
  @override
  Stream<NearbyChanges> watch(GeohashBound bound) {
    final probe = QueryProbe(bound);
    probes.add(probe);
    return probe.events;
  }

  @override
  Stream<Map<String, dynamic>?> watchVendor(String uid) =>
      (vendorStreams[uid] ??= StreamController<Map<String, dynamic>?>.broadcast(
        sync: true,
      )).stream;
  void seed(List<NearbyDocument> docs) {
    for (final p in probes.where((p) => p.active)) {
      p.add(
        docs
            .where((d) => p.bound.contains(d.data['geohash'] as String? ?? ''))
            .toList(),
      );
    }
  }
}

class TestCustomerLocation extends LocationService {
  StoreLocation result = StoreLocation(0, 0);
  Object? failure;
  Completer<StoreLocation>? gate;
  @override
  Future<StoreLocation> suggest() async {
    if (failure != null) throw failure!;
    return gate == null ? result : gate!.future;
  }
}

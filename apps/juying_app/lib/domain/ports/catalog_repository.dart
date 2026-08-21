import '../models/media_source.dart';

abstract interface class CatalogRepository {
  Future<List<MediaSource>> listSources();
  Future<void> refresh(String sourceId);
}

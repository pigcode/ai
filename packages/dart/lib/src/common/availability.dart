/// Analysis Server API version.
///
/// This is deliberately not interchangeable with [VmServiceWireVersion].
final class AnalysisServerApiVersion
    implements Comparable<AnalysisServerApiVersion> {
  const AnalysisServerApiVersion(this.major, this.minor, this.patch)
      : assert(major >= 0),
        assert(minor >= 0),
        assert(patch >= 0);

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AnalysisServerApiVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) {
      return majorOrder;
    }
    final minorOrder = minor.compareTo(other.minor);
    return minorOrder != 0 ? minorOrder : patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is AnalysisServerApiVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// VM Service wire version.
///
/// This is deliberately not interchangeable with [AnalysisServerApiVersion].
final class VmServiceWireVersion implements Comparable<VmServiceWireVersion> {
  const VmServiceWireVersion(this.major, this.minor)
      : assert(major >= 0),
        assert(minor >= 0);

  final int major;
  final int minor;

  @override
  int compareTo(VmServiceWireVersion other) {
    final majorOrder = major.compareTo(other.major);
    return majorOrder != 0 ? majorOrder : minor.compareTo(other.minor);
  }

  @override
  bool operator ==(Object other) =>
      other is VmServiceWireVersion &&
      major == other.major &&
      minor == other.minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

/// Supported inclusive Analysis Server API range.
final class AnalysisServerVersionPolicy {
  factory AnalysisServerVersionPolicy({
    required AnalysisServerApiVersion minimum,
    required AnalysisServerApiVersion current,
  }) {
    if (minimum.compareTo(current) > 0) {
      throw ArgumentError.value(
        minimum,
        'minimum',
        'Must not be newer than current.',
      );
    }
    return AnalysisServerVersionPolicy._(
      minimum: minimum,
      current: current,
    );
  }

  const AnalysisServerVersionPolicy._({
    required this.minimum,
    required this.current,
  });

  final AnalysisServerApiVersion minimum;
  final AnalysisServerApiVersion current;

  bool supports(AnalysisServerApiVersion version) =>
      minimum.compareTo(version) <= 0 && current.compareTo(version) >= 0;
}

/// DTD availability policy keyed only by the fixed inventory revision.
final class DtdInventoryPolicy {
  const DtdInventoryPolicy({required this.inventoryRevision})
      : assert(inventoryRevision != '');

  final String inventoryRevision;

  bool accepts(String revision) => revision == inventoryRevision;
}

/// Supported VM Service major and inclusive minor range.
final class VmServiceVersionPolicy {
  const VmServiceVersionPolicy({
    required this.supportedMajor,
    required this.minimumMinor,
    required this.currentMinor,
  })  : assert(supportedMajor >= 0),
        assert(minimumMinor >= 0),
        assert(minimumMinor <= currentMinor);

  final int supportedMajor;
  final int minimumMinor;
  final int currentMinor;

  bool supports(VmServiceWireVersion version) =>
      version.major == supportedMajor &&
      version.minor >= minimumMinor &&
      version.minor <= currentMinor;
}

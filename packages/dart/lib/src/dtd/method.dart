enum DtdMethodKind {
  request,
  notification,
  dynamicService,
}

final class DtdMethodDescriptor {
  const DtdMethodDescriptor({
    required this.name,
    required this.kind,
    required this.resultType,
  });

  final String name;
  final DtdMethodKind kind;
  final String? resultType;
}
